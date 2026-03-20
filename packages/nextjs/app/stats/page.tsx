"use client";

import type { NextPage } from "next";
import { formatEther } from "viem";
import { useScaffoldReadContract } from "~~/hooks/scaffold-eth";

const Stats: NextPage = () => {
  const { data: totalSupply } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "totalSupply",
  });

  const { data: accountedWeETH } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "accountedWeETH",
  });

  const { data: totalClawdBurned } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "totalClawdBurned",
  });

  const { data: totalClawdDistributed } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "totalClawdDistributed",
  });

  const { data: lastHarvestTimestamp } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "lastHarvestTimestamp",
  });

  const { data: harvestableYield } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "harvestableYield",
  });

  const { data: accRewardsPerShare } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "accRewardsPerShare",
  });

  const fmt = (val: bigint | undefined, decimals = 4) => {
    if (val === undefined) return "—";
    return parseFloat(formatEther(val)).toFixed(decimals);
  };

  const fmtTimestamp = (ts: bigint | undefined) => {
    if (ts === undefined || ts === 0n) return "Never";
    return new Date(Number(ts) * 1000).toLocaleString();
  };

  return (
    <div className="flex flex-col items-center grow pt-8 px-4">
      <h1 className="text-3xl font-bold mb-8">📊 Protocol Stats</h1>

      <div className="w-full max-w-4xl space-y-6 pb-10">
        {/* ─── TVL ──────────────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl">
          <div className="card-body">
            <h2 className="card-title text-xl">Total Value Locked</h2>
            <div className="stats stats-vertical md:stats-horizontal w-full">
              <div className="stat">
                <div className="stat-title">weETH Deposited</div>
                <div className="stat-value text-2xl">{fmt(accountedWeETH)}</div>
                <div className="stat-desc">Tracked by accountedWeETH</div>
              </div>
              <div className="stat">
                <div className="stat-title">clawdETH Supply</div>
                <div className="stat-value text-2xl">{fmt(totalSupply)}</div>
                <div className="stat-desc">Total clawdETH tokens minted</div>
              </div>
              <div className="stat">
                <div className="stat-title">Harvestable Surplus</div>
                <div className="stat-value text-2xl text-accent">{fmt(harvestableYield)}</div>
                <div className="stat-desc">weETH yield ready to harvest</div>
              </div>
            </div>
          </div>
        </div>

        {/* ─── CLAWD Impact ─────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl">
          <div className="card-body">
            <h2 className="card-title text-xl">🔥 CLAWD Impact</h2>
            <div className="stats stats-vertical md:stats-horizontal w-full">
              <div className="stat">
                <div className="stat-title">Total CLAWD Burned</div>
                <div className="stat-value text-2xl text-error">{fmt(totalClawdBurned)}</div>
                <div className="stat-desc">Sent to 0x...dEaD forever</div>
              </div>
              <div className="stat">
                <div className="stat-title">Total CLAWD Distributed</div>
                <div className="stat-value text-2xl text-primary">{fmt(totalClawdDistributed)}</div>
                <div className="stat-desc">Pro-rata to clawdETH holders</div>
              </div>
              <div className="stat">
                <div className="stat-title">Rewards Per Share</div>
                <div className="stat-value text-2xl">{fmt(accRewardsPerShare, 8)}</div>
                <div className="stat-desc">Accumulated CLAWD per clawdETH</div>
              </div>
            </div>
          </div>
        </div>

        {/* ─── Harvest Info ──────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl">
          <div className="card-body">
            <h2 className="card-title text-xl">🌾 Harvest Info</h2>
            <div className="stats stats-vertical md:stats-horizontal w-full">
              <div className="stat">
                <div className="stat-title">Last Harvest</div>
                <div className="stat-value text-lg">{fmtTimestamp(lastHarvestTimestamp)}</div>
              </div>
              <div className="stat">
                <div className="stat-title">Harvest Incentive</div>
                <div className="stat-value text-lg">1%</div>
                <div className="stat-desc">Of CLAWD bought goes to caller</div>
              </div>
              <div className="stat">
                <div className="stat-title">Min Harvest Amount</div>
                <div className="stat-value text-lg">0.001</div>
                <div className="stat-desc">weETH surplus needed</div>
              </div>
            </div>
          </div>
        </div>

        {/* ─── Contract Details ─────────────────────────── */}
        <div className="card bg-base-200 shadow-xl">
          <div className="card-body">
            <h2 className="card-title text-xl">📋 Contract Details</h2>
            <div className="overflow-x-auto">
              <table className="table">
                <tbody>
                  <tr>
                    <td className="font-semibold">Chain</td>
                    <td>Base (8453)</td>
                  </tr>
                  <tr>
                    <td className="font-semibold">Yield Source</td>
                    <td className="font-mono text-sm">weETH: 0x04C0...150A</td>
                  </tr>
                  <tr>
                    <td className="font-semibold">CLAWD Token</td>
                    <td className="font-mono text-sm">0x9f86...b07</td>
                  </tr>
                  <tr>
                    <td className="font-semibold">DEX</td>
                    <td>Uniswap V3 SwapRouter on Base</td>
                  </tr>
                  <tr>
                    <td className="font-semibold">Burn Split</td>
                    <td>50% burned / 49% distributed / 1% harvester</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Stats;
