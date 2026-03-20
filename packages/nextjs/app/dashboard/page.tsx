"use client";

import { useState } from "react";
import type { NextPage } from "next";
import { formatEther, parseEther } from "viem";
import { useAccount, useBalance } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

type ButtonState = "idle" | "loading" | "mining" | "done";

const Dashboard: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const { data: ethBalance } = useBalance({ address: connectedAddress });

  // ─── Form state ──────────────────────────────────────────
  const [depositAmount, setDepositAmount] = useState("");
  const [weethDepositAmount, setWeethDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [depositBtnState, setDepositBtnState] = useState<ButtonState>("idle");
  const [weethDepositBtnState, setWeethDepositBtnState] = useState<ButtonState>("idle");
  const [withdrawBtnState, setWithdrawBtnState] = useState<ButtonState>("idle");
  const [withdrawEthBtnState, setWithdrawEthBtnState] = useState<ButtonState>("idle");
  const [claimBtnState, setClaimBtnState] = useState<ButtonState>("idle");
  const [harvestBtnState, setHarvestBtnState] = useState<ButtonState>("idle");

  // ─── Contract reads ──────────────────────────────────────
  const { data: clawdETHBalance } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "balanceOf",
    args: [connectedAddress],
  });

  const { data: pendingRewards } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "getRewards",
    args: [connectedAddress],
  });

  const { data: harvestableYield } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "harvestableYield",
  });

  const { data: totalSupply } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "totalSupply",
  });

  const { data: accountedWeETH } = useScaffoldReadContract({
    contractName: "ClawdETH",
    functionName: "accountedWeETH",
  });

  // ─── Contract writes ─────────────────────────────────────
  const { writeContractAsync: writeClawdETH } = useScaffoldWriteContract("ClawdETH");

  // ─── Handlers ────────────────────────────────────────────
  const handleDepositETH = async () => {
    if (!depositAmount || parseFloat(depositAmount) <= 0) return;
    try {
      setDepositBtnState("loading");
      await writeClawdETH({
        functionName: "depositETH",
        value: parseEther(depositAmount),
      });
      setDepositBtnState("done");
      setDepositAmount("");
      setTimeout(() => setDepositBtnState("idle"), 2000);
    } catch {
      setDepositBtnState("idle");
    }
  };

  const handleDepositWeETH = async () => {
    if (!weethDepositAmount || parseFloat(weethDepositAmount) <= 0) return;
    try {
      setWeethDepositBtnState("loading");
      await writeClawdETH({
        functionName: "depositWeETH",
        args: [parseEther(weethDepositAmount)],
      });
      setWeethDepositBtnState("done");
      setWeethDepositAmount("");
      setTimeout(() => setWeethDepositBtnState("idle"), 2000);
    } catch {
      setWeethDepositBtnState("idle");
    }
  };

  const handleWithdraw = async () => {
    if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) return;
    try {
      setWithdrawBtnState("loading");
      await writeClawdETH({
        functionName: "withdraw",
        args: [parseEther(withdrawAmount)],
      });
      setWithdrawBtnState("done");
      setWithdrawAmount("");
      setTimeout(() => setWithdrawBtnState("idle"), 2000);
    } catch {
      setWithdrawBtnState("idle");
    }
  };

  const handleWithdrawETH = async () => {
    if (!withdrawAmount || parseFloat(withdrawAmount) <= 0) return;
    try {
      setWithdrawEthBtnState("loading");
      await writeClawdETH({
        functionName: "withdrawETH",
        args: [parseEther(withdrawAmount)],
      });
      setWithdrawEthBtnState("done");
      setWithdrawAmount("");
      setTimeout(() => setWithdrawEthBtnState("idle"), 2000);
    } catch {
      setWithdrawEthBtnState("idle");
    }
  };

  const handleClaim = async () => {
    try {
      setClaimBtnState("loading");
      await writeClawdETH({ functionName: "claim" });
      setClaimBtnState("done");
      setTimeout(() => setClaimBtnState("idle"), 2000);
    } catch {
      setClaimBtnState("idle");
    }
  };

  const handleHarvest = async () => {
    try {
      setHarvestBtnState("loading");
      await writeClawdETH({ functionName: "harvest" });
      setHarvestBtnState("done");
      setTimeout(() => setHarvestBtnState("idle"), 2000);
    } catch {
      setHarvestBtnState("idle");
    }
  };

  const buttonLabel = (state: ButtonState, labels: { idle: string; loading: string; done: string }) => {
    switch (state) {
      case "idle":
        return labels.idle;
      case "loading":
      case "mining":
        return (
          <span className="flex items-center gap-2">
            <span className="loading loading-spinner loading-sm" />
            {labels.loading}
          </span>
        );
      case "done":
        return labels.done;
    }
  };

  const fmt = (val: bigint | undefined, decimals = 4) => {
    if (val === undefined) return "—";
    return parseFloat(formatEther(val)).toFixed(decimals);
  };

  if (!connectedAddress) {
    return (
      <div className="flex items-center justify-center grow">
        <div className="text-center">
          <h2 className="text-2xl font-bold mb-4">Connect your wallet</h2>
          <p className="text-base-content/60">Connect a wallet to deposit ETH or weETH into the clawdETH vault.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center grow pt-8 px-4">
      <h1 className="text-3xl font-bold mb-8">🐾 Dashboard</h1>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 w-full max-w-4xl">
        {/* ─── Balances Card ──────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl col-span-1 md:col-span-2">
          <div className="card-body">
            <h2 className="card-title">Your Balances</h2>
            <div className="stats stats-vertical md:stats-horizontal w-full">
              <div className="stat">
                <div className="stat-title">ETH</div>
                <div className="stat-value text-lg">
                  {ethBalance ? parseFloat(formatEther(ethBalance.value)).toFixed(4) : "—"}
                </div>
              </div>
              <div className="stat">
                <div className="stat-title">clawdETH</div>
                <div className="stat-value text-lg">{fmt(clawdETHBalance)}</div>
              </div>
              <div className="stat">
                <div className="stat-title">Claimable CLAWD</div>
                <div className="stat-value text-lg text-primary">{fmt(pendingRewards)}</div>
              </div>
            </div>
          </div>
        </div>

        {/* ─── Deposit Card ──────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Deposit</h2>

            {/* Deposit ETH */}
            <div className="form-control mt-2">
              <label className="label">
                <span className="label-text">Deposit ETH</span>
              </label>
              <div className="join w-full">
                <input
                  type="number"
                  step="0.001"
                  min="0"
                  placeholder="0.0"
                  className="input input-bordered join-item w-full"
                  value={depositAmount}
                  onChange={e => setDepositAmount(e.target.value)}
                />
                <button
                  className="btn btn-primary join-item"
                  disabled={depositBtnState !== "idle"}
                  onClick={handleDepositETH}
                >
                  {buttonLabel(depositBtnState, { idle: "Deposit ETH", loading: "Depositing…", done: "✓ Done" })}
                </button>
              </div>
              <label className="label">
                <span className="label-text-alt">Swaps ETH→weETH via Uniswap, then mints clawdETH</span>
              </label>
            </div>

            {/* Deposit weETH */}
            <div className="form-control mt-4">
              <label className="label">
                <span className="label-text">Deposit weETH</span>
              </label>
              <div className="join w-full">
                <input
                  type="number"
                  step="0.001"
                  min="0"
                  placeholder="0.0"
                  className="input input-bordered join-item w-full"
                  value={weethDepositAmount}
                  onChange={e => setWeethDepositAmount(e.target.value)}
                />
                <button
                  className="btn btn-secondary join-item"
                  disabled={weethDepositBtnState !== "idle"}
                  onClick={handleDepositWeETH}
                >
                  {buttonLabel(weethDepositBtnState, { idle: "Deposit weETH", loading: "Depositing…", done: "✓ Done" })}
                </button>
              </div>
              <label className="label">
                <span className="label-text-alt">Requires weETH approval first — mints clawdETH 1:1</span>
              </label>
            </div>
          </div>
        </div>

        {/* ─── Withdraw Card ─────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl">
          <div className="card-body">
            <h2 className="card-title">Withdraw</h2>
            <div className="form-control mt-2">
              <label className="label">
                <span className="label-text">Amount (clawdETH)</span>
              </label>
              <input
                type="number"
                step="0.001"
                min="0"
                placeholder="0.0"
                className="input input-bordered w-full"
                value={withdrawAmount}
                onChange={e => setWithdrawAmount(e.target.value)}
              />
              {clawdETHBalance && clawdETHBalance > 0n && (
                <label className="label">
                  <span
                    className="label-text-alt link link-primary"
                    onClick={() => setWithdrawAmount(formatEther(clawdETHBalance))}
                  >
                    Max: {fmt(clawdETHBalance)}
                  </span>
                </label>
              )}
            </div>
            <div className="flex gap-2 mt-2">
              <button
                className="btn btn-outline flex-1"
                disabled={withdrawBtnState !== "idle"}
                onClick={handleWithdraw}
              >
                {buttonLabel(withdrawBtnState, { idle: "Get weETH", loading: "Withdrawing…", done: "✓ Done" })}
              </button>
              <button
                className="btn btn-outline flex-1"
                disabled={withdrawEthBtnState !== "idle"}
                onClick={handleWithdrawETH}
              >
                {buttonLabel(withdrawEthBtnState, { idle: "Get ETH", loading: "Withdrawing…", done: "✓ Done" })}
              </button>
            </div>
            <p className="text-xs text-base-content/60 mt-2">
              &quot;Get weETH&quot; returns weETH directly. &quot;Get ETH&quot; swaps weETH→ETH via Uniswap.
            </p>
          </div>
        </div>

        {/* ─── Claim + Harvest Card ──────────────────────── */}
        <div className="card bg-base-200 shadow-xl col-span-1 md:col-span-2">
          <div className="card-body">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <h2 className="card-title">Claim CLAWD Rewards</h2>
                <p className="text-sm text-base-content/60 mt-1">
                  You have <strong>{fmt(pendingRewards)}</strong> CLAWD claimable.
                </p>
                <button
                  className="btn btn-primary mt-4 w-full"
                  disabled={claimBtnState !== "idle" || !pendingRewards || pendingRewards === 0n}
                  onClick={handleClaim}
                >
                  {buttonLabel(claimBtnState, { idle: "Claim CLAWD", loading: "Claiming…", done: "✓ Claimed" })}
                </button>
              </div>
              <div>
                <h2 className="card-title">Harvest Yield</h2>
                <p className="text-sm text-base-content/60 mt-1">
                  Harvestable: <strong>{fmt(harvestableYield)} weETH</strong> surplus.
                  <br />
                  Anyone can call harvest() — you get 1% of CLAWD bought as reward.
                </p>
                <button
                  className="btn btn-accent mt-4 w-full"
                  disabled={harvestBtnState !== "idle" || !harvestableYield || harvestableYield === 0n}
                  onClick={handleHarvest}
                >
                  {buttonLabel(harvestBtnState, { idle: "🌾 Harvest", loading: "Harvesting…", done: "✓ Harvested" })}
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* ─── Vault Info ────────────────────────────────── */}
        <div className="card bg-base-200 shadow-xl col-span-1 md:col-span-2 mb-10">
          <div className="card-body">
            <h2 className="card-title">Vault Info</h2>
            <div className="stats stats-vertical md:stats-horizontal w-full">
              <div className="stat">
                <div className="stat-title">Total clawdETH Supply</div>
                <div className="stat-value text-lg">{fmt(totalSupply)}</div>
              </div>
              <div className="stat">
                <div className="stat-title">weETH in Vault</div>
                <div className="stat-value text-lg">{fmt(accountedWeETH)}</div>
              </div>
              <div className="stat">
                <div className="stat-title">Harvestable Yield</div>
                <div className="stat-value text-lg text-accent">{fmt(harvestableYield)}</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
