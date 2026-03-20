// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal interface for Uniswap V3 SwapRouter
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @notice Minimal WETH interface
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title ClawdETH
 * @notice ETH yield vault using ether.fi's weETH on Base.
 *
 *  Users deposit weETH (or ETH, which is swapped to weETH via Uniswap V3)
 *  and receive clawdETH shares 1:1 with weETH deposited.
 *
 *  weETH is non-rebasing: 1 weETH becomes worth more ETH over time.
 *  harvest() captures that appreciation, swaps a portion for CLAWD,
 *  burns 50 % of the CLAWD, and distributes the other 50 % pro-rata
 *  to clawdETH holders.
 *
 *  Incentive design: harvest() is permissionless. Anyone can call it.
 *  Caller receives 1 % of the harvested CLAWD as a gas incentive,
 *  making it self-sustaining without a keeper.
 *
 * @dev Architecture decision: Lido is NOT on Base. ether.fi's weETH
 *      (0x04c0599ae5a44757c0af6f9ec3b93da8976c150a) is used instead.
 *      weETH on Base is a bridged ERC20 with no native deposit() — ETH
 *      deposits are routed through Uniswap V3 (ETH→WETH→weETH).
 */
contract ClawdETH is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Immutables ──────────────────────────────────────────────────────
    IERC20 public immutable weETH;
    IERC20 public immutable clawd;
    IWETH public immutable weth;
    ISwapRouter public immutable swapRouter;

    // ─── Constants ───────────────────────────────────────────────────────
    uint256 public constant BURN_BPS = 5000; // 50 % of CLAWD bought is burned
    uint256 public constant CALLER_BPS = 100; // 1 % of CLAWD to harvest() caller
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint24 public constant WEETH_WETH_FEE = 500; // 0.05 % Uniswap pool
    uint24 public constant WETH_CLAWD_FEE = 10_000; // 1 % Uniswap pool (illiquid)
    address public constant DEAD = address(0x000000000000000000000000000000000000dEaD);
    uint256 public constant MIN_HARVEST_AMOUNT = 0.001 ether; // min weETH to harvest

    // ─── Reward tracking (standard ERC20 dividends pattern) ─────────────
    uint256 public accRewardsPerShare; // scaled by 1e18
    mapping(address => uint256) public userRewardDebt;
    mapping(address => uint256) public userPendingRewards;

    // ─── Harvest state ──────────────────────────────────────────────────
    /// @notice weETH balance accounted for (deposits minus withdrawals).
    ///         Any excess over this is harvestable yield.
    uint256 public accountedWeETH;

    // ─── Stats ──────────────────────────────────────────────────────────
    uint256 public totalClawdBurned;
    uint256 public totalClawdDistributed;
    uint256 public lastHarvestTimestamp;

    // ─── Events ─────────────────────────────────────────────────────────
    event Deposited(address indexed user, uint256 weETHAmount, uint256 clawdETHMinted);
    event DepositedETH(address indexed user, uint256 ethAmount, uint256 weETHReceived, uint256 clawdETHMinted);
    event Withdrawn(address indexed user, uint256 clawdETHBurned, uint256 weETHReturned);
    event WithdrawnETH(address indexed user, uint256 clawdETHBurned, uint256 ethReturned);
    event Harvested(
        address indexed caller,
        uint256 weETHYield,
        uint256 clawdBought,
        uint256 clawdBurned,
        uint256 clawdDistributed,
        uint256 callerReward
    );
    event RewardsClaimed(address indexed user, uint256 clawdAmount);

    // ─── Errors ─────────────────────────────────────────────────────────
    error ZeroAmount();
    error InsufficientBalance();
    error NoYieldToHarvest();
    error SwapFailed();
    error TransferFailed();

    // ─── Constructor ────────────────────────────────────────────────────
    constructor(
        address _weETH,
        address _clawd,
        address _weth,
        address _swapRouter
    ) ERC20("clawdETH", "clawdETH") {
        weETH = IERC20(_weETH);
        clawd = IERC20(_clawd);
        weth = IWETH(_weth);
        swapRouter = ISwapRouter(_swapRouter);
    }

    // ─── Deposit ────────────────────────────────────────────────────────

    /**
     * @notice Deposit weETH directly and receive clawdETH 1:1.
     * @param amount Amount of weETH to deposit.
     */
    function depositWeETH(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _updateRewards(msg.sender);

        weETH.safeTransferFrom(msg.sender, address(this), amount);
        accountedWeETH += amount;

        _mint(msg.sender, amount);
        _updateDebt(msg.sender);

        emit Deposited(msg.sender, amount, amount);
    }

    /**
     * @notice Deposit ETH — swaps to weETH via Uniswap V3, then mints clawdETH.
     * @dev ETH → WETH → weETH via Uniswap V3 exactInputSingle.
     *      User receives clawdETH equal to the weETH received from the swap.
     */
    function depositETH() external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();

        _updateRewards(msg.sender);

        // Wrap ETH → WETH
        weth.deposit{ value: msg.value }();

        // Approve router to spend WETH
        IERC20(address(weth)).approve(address(swapRouter), msg.value);

        // Swap WETH → weETH via Uniswap V3
        uint256 weETHReceived = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(weETH),
                fee: WEETH_WETH_FEE,
                recipient: address(this),
                amountIn: msg.value,
                amountOutMinimum: 0, // Caller accepts market rate; front-end should use slippage check
                sqrtPriceLimitX96: 0
            })
        );

        accountedWeETH += weETHReceived;
        _mint(msg.sender, weETHReceived);
        _updateDebt(msg.sender);

        emit DepositedETH(msg.sender, msg.value, weETHReceived, weETHReceived);
    }

    // ─── Withdraw ───────────────────────────────────────────────────────

    /**
     * @notice Withdraw weETH by burning clawdETH 1:1.
     * @param amount Amount of clawdETH to burn.
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        _updateRewards(msg.sender);

        _burn(msg.sender, amount);
        accountedWeETH -= amount;
        _updateDebt(msg.sender);

        weETH.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, amount);
    }

    /**
     * @notice Withdraw as ETH by burning clawdETH, swapping weETH → WETH → ETH.
     * @param amount Amount of clawdETH to burn.
     */
    function withdrawETH(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        _updateRewards(msg.sender);

        _burn(msg.sender, amount);
        accountedWeETH -= amount;
        _updateDebt(msg.sender);

        // Approve router to spend weETH
        IERC20(address(weETH)).approve(address(swapRouter), amount);

        // Swap weETH → WETH via Uniswap V3
        uint256 wethReceived = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weETH),
                tokenOut: address(weth),
                fee: WEETH_WETH_FEE,
                recipient: address(this),
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Unwrap WETH → ETH
        weth.withdraw(wethReceived);

        // Send ETH to user
        (bool success,) = msg.sender.call{ value: wethReceived }("");
        if (!success) revert TransferFailed();

        emit WithdrawnETH(msg.sender, amount, wethReceived);
    }

    // ─── Harvest ────────────────────────────────────────────────────────

    /**
     * @notice Harvest yield from weETH appreciation.
     *
     *  Anyone can call this — the caller receives 1 % of the CLAWD purchased
     *  as a gas incentive. No keeper needed.
     *
     *  Yield = actual weETH balance - accountedWeETH.
     *  This surplus comes from weETH appreciation or direct weETH donations.
     *
     *  Flow:
     *    1. Calculate harvestable weETH
     *    2. Swap weETH → WETH → CLAWD via Uniswap V3
     *    3. Burn 50 % of CLAWD (sent to dead address)
     *    4. 1 % of CLAWD to caller (gas incentive)
     *    5. Remaining ~49 % distributed pro-rata to clawdETH holders
     */
    function harvest() external nonReentrant {
        uint256 currentBalance = weETH.balanceOf(address(this));
        uint256 yield_ = currentBalance > accountedWeETH ? currentBalance - accountedWeETH : 0;

        if (yield_ < MIN_HARVEST_AMOUNT) revert NoYieldToHarvest();
        if (totalSupply() == 0) revert NoYieldToHarvest();

        // Approve router to spend weETH yield
        IERC20(address(weETH)).approve(address(swapRouter), yield_);

        // Swap weETH → WETH → CLAWD (two hops)
        // First: weETH → WETH
        uint256 wethReceived = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weETH),
                tokenOut: address(weth),
                fee: WEETH_WETH_FEE,
                recipient: address(this),
                amountIn: yield_,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Second: WETH → CLAWD
        IERC20(address(weth)).approve(address(swapRouter), wethReceived);
        uint256 clawdBought = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(clawd),
                fee: WETH_CLAWD_FEE,
                recipient: address(this),
                amountIn: wethReceived,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Distribute CLAWD
        uint256 burnAmount = (clawdBought * BURN_BPS) / BPS_DENOMINATOR;
        uint256 callerReward = (clawdBought * CALLER_BPS) / BPS_DENOMINATOR;
        uint256 holderShare = clawdBought - burnAmount - callerReward;

        // Burn 50 % (send to dead address since CLAWD may not have burn())
        clawd.safeTransfer(DEAD, burnAmount);
        totalClawdBurned += burnAmount;

        // 1 % to caller
        clawd.safeTransfer(msg.sender, callerReward);

        // ~49 % distributed pro-rata to holders
        accRewardsPerShare += (holderShare * 1e18) / totalSupply();
        totalClawdDistributed += holderShare;

        lastHarvestTimestamp = block.timestamp;

        emit Harvested(msg.sender, yield_, clawdBought, burnAmount, holderShare, callerReward);
    }

    // ─── Claim ──────────────────────────────────────────────────────────

    /**
     * @notice Claim accumulated CLAWD rewards.
     */
    function claim() external nonReentrant {
        _updateRewards(msg.sender);

        uint256 pending = userPendingRewards[msg.sender];
        if (pending == 0) revert ZeroAmount();

        userPendingRewards[msg.sender] = 0;
        _updateDebt(msg.sender);

        clawd.safeTransfer(msg.sender, pending);

        emit RewardsClaimed(msg.sender, pending);
    }

    // ─── View functions ─────────────────────────────────────────────────

    /**
     * @notice Get pending CLAWD rewards for an address.
     */
    function getRewards(address user) external view returns (uint256) {
        uint256 pending = userPendingRewards[user];
        if (balanceOf(user) > 0) {
            pending += (balanceOf(user) * accRewardsPerShare) / 1e18 - userRewardDebt[user];
        }
        return pending;
    }

    /**
     * @notice Get the current harvestable weETH yield.
     */
    function harvestableYield() external view returns (uint256) {
        uint256 currentBalance = weETH.balanceOf(address(this));
        return currentBalance > accountedWeETH ? currentBalance - accountedWeETH : 0;
    }

    // ─── Internal ───────────────────────────────────────────────────────

    /// @dev Snapshot pending rewards before balance changes.
    function _updateRewards(address user) internal {
        if (balanceOf(user) > 0) {
            userPendingRewards[user] += (balanceOf(user) * accRewardsPerShare) / 1e18 - userRewardDebt[user];
        }
    }

    /// @dev Set debt to current share after balance change.
    function _updateDebt(address user) internal {
        userRewardDebt[user] = (balanceOf(user) * accRewardsPerShare) / 1e18;
    }

    /// @dev Override transfers to update rewards for both sender and receiver.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            _updateRewards(from);
        }
        if (to != address(0)) {
            _updateRewards(to);
        }

        super._update(from, to, value);

        if (from != address(0)) {
            _updateDebt(from);
        }
        if (to != address(0)) {
            _updateDebt(to);
        }
    }

    /// @notice Accept ETH (for WETH unwrapping during withdrawETH).
    receive() external payable { }
}
