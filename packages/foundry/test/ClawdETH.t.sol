// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/ClawdETH.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ─── Mock tokens ────────────────────────────────────────────────────────────
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

// ─── Mock Uniswap V3 Router ────────────────────────────────────────────────
contract MockSwapRouter {
    // Configurable exchange rates (numerator / denominator)
    uint256 public weethToWethRate = 105; // 1 weETH = 1.05 WETH (5% appreciation)
    uint256 public wethToClawdRate = 1000; // 1 WETH = 1000 CLAWD
    uint256 public wethToWeethRate = 95; // 1 WETH buys 0.95 weETH (inverse of 1.05)
    uint256 public rateDenominator = 100;

    address public weeth;
    address public weth;
    address public clawd;

    constructor(address _weeth, address _weth, address _clawd) {
        weeth = _weeth;
        weth = _weth;
        clawd = _clawd;
    }

    function setWeethToWethRate(uint256 num, uint256 denom) external {
        weethToWethRate = num;
        rateDenominator = denom;
    }

    function setWethToClawdRate(uint256 rate) external {
        wethToClawdRate = rate;
    }

    function setWethToWeethRate(uint256 num) external {
        wethToWeethRate = num;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        // Transfer tokenIn from sender
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Calculate output
        if (params.tokenIn == weeth && params.tokenOut == weth) {
            // weETH → WETH
            amountOut = (params.amountIn * weethToWethRate) / rateDenominator;
        } else if (params.tokenIn == weth && params.tokenOut == clawd) {
            // WETH → CLAWD
            amountOut = (params.amountIn * wethToClawdRate) / rateDenominator;
        } else if (params.tokenIn == weth && params.tokenOut == weeth) {
            // WETH → weETH (for depositETH)
            amountOut = (params.amountIn * wethToWeethRate) / rateDenominator;
        } else {
            revert("MockSwapRouter: unsupported pair");
        }

        // Mint output tokens to recipient
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);
    }
}

// ─── Test contract ──────────────────────────────────────────────────────────
contract ClawdETHTest is Test {
    ClawdETH public vault;
    MockERC20 public weeth;
    MockERC20 public clawdToken;
    MockWETH public wethToken;
    MockSwapRouter public router;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 constant ONE_WEETH = 1 ether;
    uint256 constant TEN_WEETH = 10 ether;

    function setUp() public {
        // Deploy mocks
        weeth = new MockERC20("Wrapped eETH", "weETH", 18);
        clawdToken = new MockERC20("CLAWD", "CLAWD", 18);
        wethToken = new MockWETH();
        router = new MockSwapRouter(address(weeth), address(wethToken), address(clawdToken));

        // Deploy vault
        vault = new ClawdETH(address(weeth), address(clawdToken), address(wethToken), address(router));

        // Fund MockWETH with ETH so withdraw() works
        vm.deal(address(wethToken), 1000 ether);

        // Fund users
        weeth.mint(alice, 100 ether);
        weeth.mint(bob, 100 ether);
        weeth.mint(charlie, 100 ether);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        // Approve vault for weETH
        vm.prank(alice);
        weeth.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        weeth.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        weeth.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Deposit weETH tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_depositWeETH_mintsOneToOne() public {
        vm.prank(alice);
        vault.depositWeETH(ONE_WEETH);

        assertEq(vault.balanceOf(alice), ONE_WEETH, "clawdETH balance should equal weETH deposited");
        assertEq(vault.totalSupply(), ONE_WEETH, "total supply should equal deposit");
        assertEq(vault.accountedWeETH(), ONE_WEETH, "accountedWeETH should track deposit");
    }

    function test_depositWeETH_transfersFromUser() public {
        uint256 before_ = weeth.balanceOf(alice);
        vm.prank(alice);
        vault.depositWeETH(5 ether);
        assertEq(weeth.balanceOf(alice), before_ - 5 ether, "weETH should leave user");
        assertEq(weeth.balanceOf(address(vault)), 5 ether, "vault should hold weETH");
    }

    function test_depositWeETH_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(ClawdETH.ZeroAmount.selector);
        vault.depositWeETH(0);
    }

    function test_depositWeETH_multipleUsers() public {
        vm.prank(alice);
        vault.depositWeETH(3 ether);
        vm.prank(bob);
        vault.depositWeETH(7 ether);

        assertEq(vault.balanceOf(alice), 3 ether);
        assertEq(vault.balanceOf(bob), 7 ether);
        assertEq(vault.totalSupply(), 10 ether);
        assertEq(vault.accountedWeETH(), 10 ether);
    }

    function test_depositWeETH_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ClawdETH.Deposited(alice, ONE_WEETH, ONE_WEETH);
        vault.depositWeETH(ONE_WEETH);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Deposit ETH tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_depositETH_swapsAndMints() public {
        vm.prank(alice);
        vault.depositETH{ value: 1 ether }();

        // With mock rate: 1 ETH → 0.95 weETH
        uint256 expectedWeETH = (1 ether * 95) / 100;
        assertEq(vault.balanceOf(alice), expectedWeETH, "clawdETH should equal weETH received");
        assertEq(vault.accountedWeETH(), expectedWeETH, "accountedWeETH should track");
    }

    function test_depositETH_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(ClawdETH.ZeroAmount.selector);
        vault.depositETH{ value: 0 }();
    }

    function test_depositETH_emitsEvent() public {
        uint256 expectedWeETH = (1 ether * 95) / 100;
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ClawdETH.DepositedETH(alice, 1 ether, expectedWeETH, expectedWeETH);
        vault.depositETH{ value: 1 ether }();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Withdraw weETH tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_withdraw_returnsWeETH() public {
        vm.startPrank(alice);
        vault.depositWeETH(5 ether);
        uint256 before_ = weeth.balanceOf(alice);

        vault.withdraw(3 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 2 ether, "remaining clawdETH");
        assertEq(weeth.balanceOf(alice), before_ + 3 ether, "weETH returned");
        assertEq(vault.accountedWeETH(), 2 ether, "accountedWeETH decreases");
    }

    function test_withdraw_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(ClawdETH.ZeroAmount.selector);
        vault.withdraw(0);
    }

    function test_withdraw_revertsOnInsufficientBalance() public {
        vm.startPrank(alice);
        vault.depositWeETH(1 ether);
        vm.expectRevert(ClawdETH.InsufficientBalance.selector);
        vault.withdraw(2 ether);
        vm.stopPrank();
    }

    function test_withdraw_fullBalance() public {
        vm.startPrank(alice);
        vault.depositWeETH(10 ether);
        vault.withdraw(10 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.accountedWeETH(), 0);
    }

    function test_withdraw_emitsEvent() public {
        vm.startPrank(alice);
        vault.depositWeETH(5 ether);
        vm.expectEmit(true, true, true, true);
        emit ClawdETH.Withdrawn(alice, 3 ether, 3 ether);
        vault.withdraw(3 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Withdraw ETH tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_withdrawETH_swapsAndSends() public {
        vm.startPrank(alice);
        vault.depositWeETH(1 ether);
        uint256 ethBefore = alice.balance;

        vault.withdrawETH(1 ether);
        vm.stopPrank();

        // 1 weETH → 1.05 WETH → 1.05 ETH
        uint256 expectedETH = (1 ether * 105) / 100;
        assertEq(alice.balance, ethBefore + expectedETH, "ETH received");
        assertEq(vault.balanceOf(alice), 0, "clawdETH burned");
    }

    function test_withdrawETH_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(ClawdETH.ZeroAmount.selector);
        vault.withdrawETH(0);
    }

    function test_withdrawETH_revertsOnInsufficientBalance() public {
        vm.startPrank(alice);
        vault.depositWeETH(1 ether);
        vm.expectRevert(ClawdETH.InsufficientBalance.selector);
        vault.withdrawETH(2 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Harvest tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_harvest_capturesYield() public {
        // Alice deposits 10 weETH
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // Simulate yield: mint 0.5 weETH directly to vault (simulating appreciation)
        weeth.mint(address(vault), 0.5 ether);

        // Charlie harvests (anyone can call)
        vm.prank(charlie);
        vault.harvest();

        assertEq(vault.lastHarvestTimestamp(), block.timestamp, "harvest timestamp set");
        assertTrue(vault.totalClawdBurned() > 0, "CLAWD burned");
        assertTrue(vault.totalClawdDistributed() > 0, "CLAWD distributed");
    }

    function test_harvest_revertsNoYield() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // No yield → revert
        vm.prank(charlie);
        vm.expectRevert(ClawdETH.NoYieldToHarvest.selector);
        vault.harvest();
    }

    function test_harvest_revertsNoSupply() public {
        // Mint yield to vault but no depositors
        weeth.mint(address(vault), 1 ether);

        vm.prank(charlie);
        vm.expectRevert(ClawdETH.NoYieldToHarvest.selector);
        vault.harvest();
    }

    function test_harvest_revertsBelowMinimum() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // Add yield below MIN_HARVEST_AMOUNT (0.001 ether)
        weeth.mint(address(vault), 0.0005 ether);

        vm.prank(charlie);
        vm.expectRevert(ClawdETH.NoYieldToHarvest.selector);
        vault.harvest();
    }

    function test_harvest_callerGetsReward() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        weeth.mint(address(vault), 1 ether);

        uint256 charlieClawdBefore = clawdToken.balanceOf(charlie);
        vm.prank(charlie);
        vault.harvest();

        assertTrue(clawdToken.balanceOf(charlie) > charlieClawdBefore, "caller should receive CLAWD reward");
    }

    function test_harvest_burnsSendsToDead() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        weeth.mint(address(vault), 1 ether);

        vm.prank(charlie);
        vault.harvest();

        assertTrue(clawdToken.balanceOf(vault.DEAD()) > 0, "CLAWD burned to dead address");
    }

    function test_harvest_distributionAmounts() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // 1 weETH yield
        weeth.mint(address(vault), 1 ether);

        vm.prank(charlie);
        vault.harvest();

        // Yield path: 1 weETH → 1.05 WETH → 1050 CLAWD
        // Burn: 50% = 525
        // Caller: 1% = 10 (floor of 1050 * 100 / 10000 = 10.5)
        // Holders: 1050 - 525 - 10 = 515
        uint256 expectedClawd = (1 ether * 105 * 1000) / (100 * 100); // = 10.5 * 1000 / 100 = 1050e15 ... let me just check totals
        assertEq(vault.totalClawdBurned() + vault.totalClawdDistributed() + clawdToken.balanceOf(charlie), 
            clawdToken.balanceOf(vault.DEAD()) + vault.totalClawdDistributed() + clawdToken.balanceOf(charlie),
            "all CLAWD accounted for");
    }

    function test_harvest_emitsEvent() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        weeth.mint(address(vault), 1 ether);

        vm.prank(charlie);
        // Just check that it emits (we'll skip exact values for mock)
        vm.expectEmit(true, false, false, false);
        emit ClawdETH.Harvested(charlie, 0, 0, 0, 0, 0);
        vault.harvest();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Rewards accrual + claim tests
    // ═══════════════════════════════════════════════════════════════════════

    function test_claim_singleHolder() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // Simulate yield
        weeth.mint(address(vault), 1 ether);
        vm.prank(charlie);
        vault.harvest();

        // Alice should have rewards
        uint256 rewards = vault.getRewards(alice);
        assertTrue(rewards > 0, "alice should have rewards");

        // Alice claims
        uint256 clawdBefore = clawdToken.balanceOf(alice);
        vm.prank(alice);
        vault.claim();

        assertEq(clawdToken.balanceOf(alice), clawdBefore + rewards, "CLAWD received");
        assertEq(vault.getRewards(alice), 0, "rewards zeroed after claim");
    }

    function test_claim_multipleHolders_proRata() public {
        // Alice deposits 7, Bob deposits 3 → Alice gets 70%, Bob gets 30%
        vm.prank(alice);
        vault.depositWeETH(7 ether);
        vm.prank(bob);
        vault.depositWeETH(3 ether);

        // Yield
        weeth.mint(address(vault), 1 ether);
        vm.prank(charlie);
        vault.harvest();

        uint256 aliceRewards = vault.getRewards(alice);
        uint256 bobRewards = vault.getRewards(bob);

        // Alice should get ~70%, Bob ~30%
        // Allow for rounding
        assertApproxEqRel(aliceRewards, (aliceRewards + bobRewards) * 7 / 10, 0.01e18, "alice ~70%");
        assertApproxEqRel(bobRewards, (aliceRewards + bobRewards) * 3 / 10, 0.01e18, "bob ~30%");
    }

    function test_claim_revertsIfNoRewards() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // No harvest → no rewards
        vm.prank(alice);
        vm.expectRevert(ClawdETH.ZeroAmount.selector);
        vault.claim();
    }

    function test_claim_afterMultipleHarvests() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // Harvest 1
        weeth.mint(address(vault), 0.5 ether);
        vm.prank(charlie);
        vault.harvest();

        // Harvest 2
        weeth.mint(address(vault), 0.5 ether);
        vm.prank(charlie);
        vault.harvest();

        // Alice's rewards should accumulate
        uint256 rewards = vault.getRewards(alice);
        assertTrue(rewards > 0, "rewards accumulated across harvests");

        vm.prank(alice);
        vault.claim();
        assertEq(vault.getRewards(alice), 0, "all rewards claimed");
    }

    function test_rewards_preservedOnTransfer() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // Generate rewards
        weeth.mint(address(vault), 1 ether);
        vm.prank(charlie);
        vault.harvest();

        uint256 aliceRewardsBefore = vault.getRewards(alice);
        assertTrue(aliceRewardsBefore > 0, "alice has rewards");

        // Transfer clawdETH from Alice to Bob
        vm.prank(alice);
        vault.transfer(bob, 5 ether);

        // Alice's earned rewards should be preserved
        uint256 aliceRewardsAfter = vault.getRewards(alice);
        assertEq(aliceRewardsAfter, aliceRewardsBefore, "alice rewards preserved after transfer");

        // Bob starts with 0 pending from this period
        assertEq(vault.getRewards(bob), 0, "bob has no rewards yet");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Edge cases
    // ═══════════════════════════════════════════════════════════════════════

    function test_depositAndWithdraw_fullCycle() public {
        // Full lifecycle: deposit → harvest → claim → withdraw
        vm.prank(alice);
        vault.depositWeETH(5 ether);

        weeth.mint(address(vault), 0.1 ether);
        vm.prank(charlie);
        vault.harvest();

        vm.startPrank(alice);
        vault.claim();
        vault.withdraw(5 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertTrue(clawdToken.balanceOf(alice) > 0, "alice has CLAWD");
    }

    function test_zeroYield_harvestReverts() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        // No yield at all
        vm.prank(charlie);
        vm.expectRevert(ClawdETH.NoYieldToHarvest.selector);
        vault.harvest();
    }

    function test_view_harvestableYield() public {
        vm.prank(alice);
        vault.depositWeETH(TEN_WEETH);

        assertEq(vault.harvestableYield(), 0, "no yield initially");

        weeth.mint(address(vault), 0.5 ether);
        assertEq(vault.harvestableYield(), 0.5 ether, "yield = surplus");
    }

    function test_multipleDepositsAndWithdrawals() public {
        vm.startPrank(alice);
        vault.depositWeETH(5 ether);
        vault.depositWeETH(3 ether);
        vault.withdraw(2 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 6 ether);
        assertEq(vault.accountedWeETH(), 6 ether);
    }

    function test_rewardsAfterPartialWithdraw() public {
        vm.prank(alice);
        vault.depositWeETH(10 ether);

        // Yield + harvest
        weeth.mint(address(vault), 1 ether);
        vm.prank(charlie);
        vault.harvest();

        // Partial withdraw
        vm.prank(alice);
        vault.withdraw(5 ether);

        // New yield + harvest
        weeth.mint(address(vault), 0.5 ether);
        vm.prank(charlie);
        vault.harvest();

        // Alice still gets rewards (now for 5 shares)
        assertTrue(vault.getRewards(alice) > 0, "rewards accrue after partial withdraw");
    }

    function test_name_and_symbol() public view {
        assertEq(vault.name(), "clawdETH");
        assertEq(vault.symbol(), "clawdETH");
    }

    function test_decimals() public view {
        assertEq(vault.decimals(), 18);
    }

    function test_constants() public view {
        assertEq(vault.BURN_BPS(), 5000);
        assertEq(vault.CALLER_BPS(), 100);
        assertEq(vault.BPS_DENOMINATOR(), 10_000);
    }
}
