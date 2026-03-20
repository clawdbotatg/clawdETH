# 🐾 clawdETH

**ETH yield that buys & burns CLAWD**

clawdETH is an ETH yield vault on Base that uses ether.fi's weETH as a yield source. Deposited ETH earns staking yield, which is periodically harvested and used to buy CLAWD tokens via Uniswap V3. 50% of purchased CLAWD is burned forever, 50% is distributed to clawdETH holders.

## Architecture

| Component | Details |
|-----------|---------|
| **Chain** | Base (8453) |
| **Yield Source** | ether.fi weETH (`0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A`) |
| **CLAWD Token** | `0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07` |
| **DEX** | Uniswap V3 SwapRouter (`0x2626664c2603336E57B271c5C0b26F421741e481`) |
| **Contract** | ClawdETH.sol — single contract |

### Why weETH, not stETH?

**Lido is not deployed on Base.** ether.fi's weETH is the premier ETH liquid staking token on Base with deep Uniswap V3 liquidity. weETH is non-rebasing — it appreciates in ETH value over time.

## How It Works

1. **Deposit** ETH or weETH → receive clawdETH tokens 1:1 with weETH deposited
2. **weETH appreciates** in value over time (ETH staking yield)
3. **Anyone calls `harvest()`** → surplus weETH is swapped for CLAWD via Uniswap V3
   - 50% of CLAWD → burned (sent to `0xdead`)
   - 49% of CLAWD → distributed pro-rata to clawdETH holders
   - 1% of CLAWD → harvest caller (gas incentive)
4. **Claim** accumulated CLAWD rewards anytime
5. **Withdraw** your weETH (or swap back to ETH) anytime

## Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) (v18+)
- [Yarn](https://yarnpkg.com/) (v3+)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install

```bash
git clone https://github.com/clawdbotatg/clawdETH.git
cd clawdETH
yarn install
```

### Run Locally

```bash
# Terminal 1: Start local chain (Base fork)
yarn chain

# Terminal 2: Deploy contracts
yarn deploy

# Terminal 3: Start frontend
yarn start
```

### Run Tests

```bash
cd packages/foundry
forge test -vvv
```

37 tests covering deposits, withdrawals, harvest, rewards, and edge cases.

### Deploy to Base Mainnet

```bash
cd packages/foundry

# Create .env with your deployer private key
echo "DEPLOYER_PRIVATE_KEY=0x..." > .env

# Deploy
forge script script/DeployClawdETH.s.sol \
  --rpc-url https://base-mainnet.g.alchemy.com/v2/YOUR_KEY \
  --broadcast \
  --verify
```

### Deploy Frontend to Vercel

```bash
cd packages/nextjs

# Build
npx next build

# Deploy (requires Vercel CLI)
vercel --prod
```

Environment variables for Vercel:
- `NEXT_PUBLIC_ALCHEMY_API_KEY` — your Alchemy API key
- `NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID` — WalletConnect project ID

## Contract Interface

| Function | Description |
|----------|-------------|
| `depositETH()` payable | Swap ETH→weETH via Uniswap, mint clawdETH |
| `depositWeETH(amount)` | Deposit weETH directly, mint clawdETH 1:1 |
| `withdraw(amount)` | Burn clawdETH, receive weETH |
| `withdrawETH(amount)` | Burn clawdETH, receive ETH (swaps via Uniswap) |
| `harvest()` | Capture yield, buy+burn CLAWD, distribute rewards |
| `claim()` | Claim accumulated CLAWD rewards |
| `getRewards(address)` | View pending CLAWD rewards |
| `harvestableYield()` | View harvestable weETH surplus |

## Project Structure

```
clawdETH/
├── packages/
│   ├── foundry/
│   │   ├── contracts/ClawdETH.sol      # Main vault contract
│   │   ├── script/DeployClawdETH.s.sol # Deploy script
│   │   └── test/ClawdETH.t.sol         # 37 tests
│   └── nextjs/
│       ├── app/page.tsx                # Landing page
│       ├── app/dashboard/page.tsx      # Deposit/withdraw/claim
│       └── app/stats/page.tsx          # TVL, burns, APY
└── SPEC.md                            # Full specification
```

## License

MIT
