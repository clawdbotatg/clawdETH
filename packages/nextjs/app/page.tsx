"use client";

import Link from "next/link";
import type { NextPage } from "next";

const Home: NextPage = () => {
  return (
    <div className="flex items-center flex-col grow pt-10">
      <div className="px-5 max-w-3xl">
        <h1 className="text-center">
          <span className="block text-4xl font-bold mb-2">🐾 clawdETH</span>
          <span className="block text-lg text-base-content/70">ETH yield that buys &amp; burns CLAWD</span>
        </h1>

        <div className="mt-10 space-y-8">
          {/* How it works */}
          <div className="card bg-base-200 shadow-xl">
            <div className="card-body">
              <h2 className="card-title text-2xl">How it works</h2>
              <div className="space-y-4 text-base-content/80">
                <div className="flex items-start gap-3">
                  <span className="badge badge-primary badge-lg mt-0.5">1</span>
                  <div>
                    <p className="font-semibold">Deposit ETH or weETH</p>
                    <p className="text-sm">
                      Your ETH is swapped to ether.fi&apos;s weETH — a liquid staking token that earns ETH yield
                      automatically.
                    </p>
                  </div>
                </div>
                <div className="flex items-start gap-3">
                  <span className="badge badge-primary badge-lg mt-0.5">2</span>
                  <div>
                    <p className="font-semibold">Receive clawdETH</p>
                    <p className="text-sm">
                      You get clawdETH tokens 1:1 with your weETH deposit. These represent your share of the vault.
                    </p>
                  </div>
                </div>
                <div className="flex items-start gap-3">
                  <span className="badge badge-primary badge-lg mt-0.5">3</span>
                  <div>
                    <p className="font-semibold">Yield → CLAWD buyback</p>
                    <p className="text-sm">
                      As weETH appreciates, anyone can call <code className="bg-base-300 px-1 rounded">harvest()</code>.
                      The yield is swapped for CLAWD tokens via Uniswap V3.
                    </p>
                  </div>
                </div>
                <div className="flex items-start gap-3">
                  <span className="badge badge-primary badge-lg mt-0.5">4</span>
                  <div>
                    <p className="font-semibold">50% Burn / 50% Distribute</p>
                    <p className="text-sm">
                      Half the CLAWD is burned forever, reducing supply. The other half is distributed pro-rata to
                      clawdETH holders.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Architecture */}
          <div className="card bg-base-200 shadow-xl">
            <div className="card-body">
              <h2 className="card-title text-2xl">Architecture</h2>
              <div className="text-base-content/80 space-y-2">
                <p>
                  <strong>Chain:</strong> Base (L2)
                </p>
                <p>
                  <strong>Yield source:</strong> ether.fi weETH —{" "}
                  <span className="text-xs font-mono">0x04C0...150A</span>
                </p>
                <p>
                  <strong>CLAWD token:</strong> <span className="text-xs font-mono">0x9f86...b07</span>
                </p>
                <p>
                  <strong>DEX:</strong> Uniswap V3 on Base
                </p>
                <p className="text-sm mt-4 text-warning">
                  ⚠️ Why weETH and not stETH? Lido is not deployed on Base. ether.fi&apos;s weETH is the premier ETH LST
                  on Base with deep liquidity.
                </p>
              </div>
            </div>
          </div>

          {/* CTA */}
          <div className="flex justify-center gap-4 pb-10">
            <Link href="/dashboard" className="btn btn-primary btn-lg">
              Launch App →
            </Link>
            <Link href="/stats" className="btn btn-outline btn-lg">
              View Stats
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
