# clawdETH — Specification

## Austin's Exact Words

> okay next build with ethskills.com is this one: https://github.com/clawdbotatg/clawdETH

---

## Overview

clawdETH is an ETH yield vault on Base (chain 8453) that:
1. Accepts ETH or weETH deposits
2. Holds weETH (ether.fi's non-rebasing liquid staking token)
3. Periodically harvests weETH appreciation as yield
4. Swaps yield for CLAWD tokens via Uniswap V3
5. Burns 50% of CLAWD, distributes 49% to holders, 1% to harvester

## Architecture Decision: weETH, Not stETH

**Lido is NOT deployed on Base.** This is a critical constraint.

ether.fi's weETH (`0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A`) is used instead:
- Native on Base (bridged ERC20)
- Non-rebasing: 1 weETH appreciates in ETH value over time
- Deep Uniswap V3 liquidity on Base (weETH/WETH 0.05% pool)
- No native `deposit()` on Base — ETH deposits routed through Uniswap swap

## Contract: ClawdETH.sol

**Single contract** — follows ethskills.com ship/SKILL.md (0-3 contracts for MVP).

### Storage Layout

| Variable | Type | Description |
|----------|------|-------------|
| `weETH` | `IERC20` immutable | weETH token address |
| `clawd` | `IERC20` immutable | CLAWD token address |
| `weth` | `IWETH` immutable | WETH address on Base |
| `swapRouter` | `ISwapRouter` immutable | Uniswap V3 SwapRouter |
| `accRewardsPerShare` | `uint256` | Accumulated CLAWD rewards per clawdETH share (×1e18) |
| `userRewardDebt` | `mapping(address => uint256)` | Reward debt per user |
| `userPendingRewards` | `mapping(address => uint256)` | Pending CLAWD per user |
| `accountedWeETH` | `uint256` | Total weETH accounted for (deposits - withdrawals) |
| `totalClawdBurned` | `uint256` | Cumulative CLAWD burned |
| `totalClawdDistributed` | `uint256` | Cumulative CLAWD distributed |
| `lastHarvestTimestamp` | `uint256` | Timestamp of last harvest |

### Functions

| Function | Visibility | Description |
|----------|-----------|-------------|
| `depositWeETH(uint256)` | external | Deposit weETH, mint clawdETH 1:1 |
| `depositETH()` | external payable | Swap ETH→weETH via Uniswap, mint clawdETH |
| `withdraw(uint256)` | external | Burn clawdETH, return weETH 1:1 |
| `withdrawETH(uint256)` | external | Burn clawdETH, swap weETH→ETH, return ETH |
| `harvest()` | external | Capture yield, buy+burn CLAWD, distribute |
| `claim()` | external | Claim accumulated CLAWD rewards |
| `getRewards(address)` | view | Get pending CLAWD for address |
| `harvestableYield()` | view | Get surplus weETH available to harvest |

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `BURN_BPS` | 5000 | 50% of CLAWD bought is burned |
| `CALLER_BPS` | 100 | 1% of CLAWD to harvest() caller |
| `BPS_DENOMINATOR` | 10000 | Basis points denominator |
| `WEETH_WETH_FEE` | 500 | 0.05% Uniswap pool tier |
| `WETH_CLAWD_FEE` | 10000 | 1% Uniswap pool tier |
| `DEAD` | 0x...dEaD | Burn address |
| `MIN_HARVEST_AMOUNT` | 0.001 ether | Min weETH to harvest |

### Yield Mechanism

weETH is non-rebasing — its price in ETH increases over time. The "yield" is measured as:

```
yield = weETH.balanceOf(vault) - accountedWeETH
```

Where `accountedWeETH` tracks deposits minus withdrawals. Any surplus comes from:
1. weETH price appreciation (primary yield source)
2. Direct weETH donations to the contract

### Harvest Flow

```
1. yield = weETH.balanceOf(this) - accountedWeETH
2. Swap yield weETH → WETH (Uniswap V3, 0.05% pool)
3. Swap WETH → CLAWD (Uniswap V3, 1% pool)
4. burnAmount = clawdBought × 50%
5. callerReward = clawdBought × 1%
6. holderShare = clawdBought - burnAmount - callerReward
7. Send burnAmount to 0xdead
8. Send callerReward to msg.sender
9. accRewardsPerShare += holderShare × 1e18 / totalSupply
```

### Reward Distribution

Standard ERC20 dividends pattern:
- `accRewardsPerShare` accumulates globally
- `userRewardDebt` tracks what a user has already "earned through"
- `userPendingRewards` stores unclaimed rewards
- On any balance change (deposit, withdraw, transfer): snapshot pending, update debt

---

## Contract Audit (per ethskills.com/audit/SKILL.md)

### 1. Reentrancy
✅ All state-changing functions use `ReentrancyGuard` (`nonReentrant` modifier).

### 2. Integer Overflow/Underflow
✅ Solidity 0.8.x with built-in overflow checks. `accRewardsPerShare` uses 1e18 scaling — at 1B CLAWD per share this would need 1e27 which fits in uint256.

### 3. Access Control
✅ No admin functions. All functions are permissionless by design. No owner, no pauser, no upgradeability.

### 4. Front-running
⚠️ `depositETH()` and `withdrawETH()` use `amountOutMinimum: 0` for Uniswap swaps. Front-end should add slippage protection. `harvest()` is permissionless so MEV is limited to sandwich attacks on the CLAWD swap, which is bounded by MIN_HARVEST_AMOUNT.

### 5. Oracle Manipulation
✅ No oracle used. Yield is measured as actual weETH balance surplus, not price-based.

### 6. Flash Loan Attacks
✅ No flash loan vectors — rewards are based on persistent share balances, not instantaneous.

### 7. Denial of Service
✅ No unbounded loops. All operations are O(1).

### 8. Gas Optimization
✅ Immutables for constructor params. No complex loops. Standard ERC20 operations.

### 9. Event Emission
✅ Events emitted for all state changes: Deposited, DepositedETH, Withdrawn, WithdrawnETH, Harvested, RewardsClaimed.

### 10. Input Validation
✅ Zero amount checks on all deposit/withdraw functions. Insufficient balance checks. Min harvest amount enforced.

### 11. Return Value Checks
✅ Uses SafeERC20 for all token transfers. Uniswap router returns are checked implicitly.

### 12. Timestamp Dependence
✅ `lastHarvestTimestamp` is informational only — not used for logic.

### 13. Visibility
✅ All functions have explicit visibility. Internal helpers are `internal`.

### 14. Proxy/Upgrade Safety
✅ Not upgradeable. No proxy pattern. No storage collision risks.

### 15. External Call Safety
✅ External calls (Uniswap swaps) are protected by reentrancy guard. ETH transfers use low-level call with success check.

### 16. Token Interaction
✅ Uses OpenZeppelin SafeERC20. Handles standard ERC20 tokens. No fee-on-transfer assumptions.

### 17. Centralization Risks
✅ No owner, no admin, no governance. Fully permissionless. No pause functionality. No emergency withdrawal by admin.

### 18. Economic Attacks
⚠️ With very low TVL, harvest() gas cost may exceed the 1% caller reward. This is by design — harvest only happens when economically viable.

### 19. Compiler/Pragma
✅ Uses `pragma solidity ^0.8.19` with OpenZeppelin 5.x. No known compiler bugs.

### 20. Documentation
✅ NatSpec on all public functions. Architecture documented in README and SPEC.

---

## Frontend Components

| Page | Route | Description |
|------|-------|-------------|
| Landing | `/` | How it works, architecture, CTA |
| Dashboard | `/dashboard` | Deposit/withdraw/claim/harvest |
| Stats | `/stats` | TVL, CLAWD burned, distribution metrics |
| Debug | `/debug` | SE2 debug contracts page |

### UX Patterns (per ethskills.com/frontend-ux/SKILL.md)
- Four-state button flow: idle → loading → mining → done
- Spinner + disable on all blockchain buttons during transactions
- Max button for withdraw amount
- Helpful tooltips on each action
- No SE2 default branding

---

## Addresses

### Base Mainnet
| Contract | Address |
|----------|---------|
| ClawdETH | TBD — not yet deployed to mainnet |
| weETH | `0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A` |
| CLAWD | `0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07` |
| WETH | `0x4200000000000000000000000000000000000006` |
| SwapRouter | `0x2626664c2603336E57B271c5C0b26F421741e481` |

---

## Test Coverage

37 tests covering:
- Deposit weETH (5 tests)
- Deposit ETH (3 tests)
- Withdraw weETH (5 tests)
- Withdraw ETH (3 tests)
- Harvest (7 tests)
- Rewards accrual + claim (5 tests)
- Edge cases (6 tests)
- Name/symbol/decimals/constants (3 tests)

---

## What's NOT Built (Phase 3+)
- Pendle integration
- Gelato keeper (use Vercel cron instead)
- Multi-sig treasury (use deployer wallet for MVP)
- Slippage protection on contract level (handled in frontend)
