"use client";

import { useState } from "react";
import { encodeAbiParameters, type Address, type Hex } from "viem";
import { useWallet } from "@/hooks/useWallet";
import { usePoolRiskState } from "@/hooks/usePoolRiskState";
import { publicClient, unichainSepolia } from "@/lib/viem";
import { Card, CardHeader } from "@/components/ui";
import { RiskBadge } from "@/components/RiskBadge";
import { mockErc20Abi, modifyRouterAbi, swapRouterAbi } from "@/lib/abi";
import { bpsToMultiplier, bpsToPercent, riskMeta, shortenHex } from "@/lib/risk";
import {
  DYNAMIC_FEE_FLAG,
  explorerTx,
  FULL_RANGE_TICK_LOWER,
  FULL_RANGE_TICK_UPPER,
  HOOK_ADDRESS,
  INTERACTIVE_POOL_ID,
  INTERACTIVE_TOKEN0,
  INTERACTIVE_TOKEN1,
  MAX_UINT256,
  MIN_SQRT_PRICE_LIMIT,
  MODIFY_ROUTER,
  SWAP_ROUTER,
  TICK_SPACING,
} from "@/lib/config";

const MINT_AMOUNT = 1_000n * 10n ** 18n;
const SENIOR_LIQUIDITY = 10n * 10n ** 18n;
const SWAP_SIZE = 20n * 10n ** 18n;
const SENIOR_SALT =
  "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex;

const POOL_KEY = {
  currency0: INTERACTIVE_TOKEN0,
  currency1: INTERACTIVE_TOKEN1,
  fee: DYNAMIC_FEE_FLAG,
  tickSpacing: TICK_SPACING,
  hooks: HOOK_ADDRESS,
} as const;

type Status =
  | { kind: "idle" }
  | { kind: "pending"; label: string }
  | { kind: "success"; label: string; tx: Hex }
  | { kind: "error"; label: string; msg: string };

function shortError(e: unknown): string {
  const anyE = e as { shortMessage?: string; message?: string };
  const m = anyE.shortMessage ?? anyE.message ?? "Transaction failed";
  return m.length > 140 ? m.slice(0, 140) + "…" : m;
}

export function Interactive() {
  const wallet = useWallet();
  const pool = usePoolRiskState(INTERACTIVE_POOL_ID);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<Status>({ kind: "idle" });

  async function run(label: string, fn: () => Promise<Hex>) {
    if (busy) return;
    setBusy(true);
    setStatus({ kind: "pending", label });
    try {
      const tx = await fn();
      await publicClient.waitForTransactionReceipt({ hash: tx });
      setStatus({ kind: "success", label, tx });
      pool.refetch();
    } catch (e) {
      setStatus({ kind: "error", label, msg: shortError(e) });
    } finally {
      setBusy(false);
    }
  }

  /** Approve `spender` for `token` if the current allowance is below `needed`. */
  async function ensureAllowance(token: Address, spender: Address, needed: bigint) {
    const client = wallet.getClient();
    if (!client || !wallet.account) throw new Error("Connect a wallet first.");
    const current = (await publicClient.readContract({
      address: token,
      abi: mockErc20Abi,
      functionName: "allowance",
      args: [wallet.account, spender],
    })) as bigint;
    if (current >= needed) return;
    const h = await client.writeContract({
      address: token,
      abi: mockErc20Abi,
      functionName: "approve",
      args: [spender, MAX_UINT256],
      account: wallet.account,
      chain: unichainSepolia,
    });
    await publicClient.waitForTransactionReceipt({ hash: h });
  }

  /** Step 1 — only needed for a wallet that has no test tokens yet. */
  async function mintTokens(): Promise<Hex> {
    const client = wallet.getClient();
    if (!client || !wallet.account) throw new Error("Connect a wallet first.");
    let last: Hex = "0x";
    for (const token of [INTERACTIVE_TOKEN0, INTERACTIVE_TOKEN1]) {
      last = await client.writeContract({
        address: token,
        abi: mockErc20Abi,
        functionName: "mint",
        args: [wallet.account, MINT_AMOUNT],
        account: wallet.account,
        chain: unichainSepolia,
      });
      await publicClient.waitForTransactionReceipt({ hash: last });
    }
    return last;
  }

  async function openSenior(): Promise<Hex> {
    const client = wallet.getClient();
    if (!client || !wallet.account) throw new Error("Connect a wallet first.");
    await ensureAllowance(INTERACTIVE_TOKEN0, MODIFY_ROUTER, MINT_AMOUNT);
    await ensureAllowance(INTERACTIVE_TOKEN1, MODIFY_ROUTER, MINT_AMOUNT);
    const hookData = encodeAbiParameters(
      [{ type: "uint8" }, { type: "address" }],
      [0, wallet.account],
    );
    return client.writeContract({
      address: MODIFY_ROUTER,
      abi: modifyRouterAbi,
      functionName: "modifyLiquidity",
      args: [
        POOL_KEY,
        {
          tickLower: FULL_RANGE_TICK_LOWER,
          tickUpper: FULL_RANGE_TICK_UPPER,
          liquidityDelta: SENIOR_LIQUIDITY,
          salt: SENIOR_SALT,
        },
        hookData,
      ],
      account: wallet.account,
      chain: unichainSepolia,
    });
  }

  async function pushVolatility(): Promise<Hex> {
    const client = wallet.getClient();
    if (!client || !wallet.account) throw new Error("Connect a wallet first.");
    await ensureAllowance(INTERACTIVE_TOKEN0, SWAP_ROUTER, SWAP_SIZE);
    return client.writeContract({
      address: SWAP_ROUTER,
      abi: swapRouterAbi,
      functionName: "swap",
      args: [
        POOL_KEY,
        {
          zeroForOne: true,
          amountSpecified: -SWAP_SIZE,
          sqrtPriceLimitX96: MIN_SQRT_PRICE_LIMIT,
        },
        { takeClaims: false, settleUsingBurn: false },
        "0x",
      ],
      account: wallet.account,
      chain: unichainSepolia,
    });
  }

  const mode = pool.state ? pool.state.mode : 0;
  const meta = riskMeta(mode);

  return (
    <Card>
      <CardHeader
        title="Interactive — drive the cross-chain loop"
        subtitle="A fresh pool that starts LOW. Swap to spike volatility and watch the Reactive controller flip it to CRISIS."
        right={
          wallet.isConnected ? (
            <span className="tabular rounded-full border border-white/10 bg-white/[0.03] px-2.5 py-1 text-xs text-zinc-300">
              {shortenHex(wallet.account ?? "0x")}
            </span>
          ) : null
        }
      />

      <div className="px-5 py-4">
        {/* Live pool state */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/[0.02] px-4 py-3">
          <div className="flex items-center gap-3">
            <span className="text-[11px] uppercase tracking-wider text-zinc-500">
              This pool
            </span>
            <RiskBadge mode={mode} />
          </div>
          <div className="flex flex-wrap gap-x-6 gap-y-1 text-xs">
            <Fact label="Fee" value={pool.state ? bpsToMultiplier(pool.state.feeMultiplierBps) : "—"} />
            <Fact label="Coverage" value={pool.state ? bpsToPercent(pool.state.coverageRatioBps) : "—"} />
            <Fact
              label="Senior deposits"
              value={pool.state ? (pool.state.seniorDepositsEnabled ? "Open" : "Halted") : "—"}
            />
          </div>
        </div>
        <p className={`mt-2 text-xs ${meta.text}`}>{meta.blurb}</p>

        {/* Wallet gating */}
        {!wallet.hasWallet ? (
          <div className="mt-4 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-200">
            No injected wallet found. Install MetaMask to drive the demo.
          </div>
        ) : !wallet.isConnected ? (
          <button
            onClick={wallet.connect}
            disabled={wallet.connecting}
            className="mt-4 rounded-lg border border-sky-500/40 bg-sky-500/10 px-4 py-2 text-sm font-medium text-sky-200 transition-colors hover:bg-sky-500/20 disabled:opacity-50"
          >
            {wallet.connecting ? "Connecting…" : "Connect wallet"}
          </button>
        ) : !wallet.isCorrectChain ? (
          <button
            onClick={wallet.switchToUnichain}
            className="mt-4 rounded-lg border border-amber-500/40 bg-amber-500/10 px-4 py-2 text-sm font-medium text-amber-200 transition-colors hover:bg-amber-500/20"
          >
            Switch to Unichain Sepolia
          </button>
        ) : (
          <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <ActionButton
              step="1"
              label="Get test tokens"
              hint="Mint both mock tokens (skip if you already have them)"
              onClick={() => run("Get test tokens", mintTokens)}
              disabled={busy}
            />
            <ActionButton
              step="2"
              label="Open Senior position"
              hint="Auto-approves, then deposits an IL-protected Senior LP"
              onClick={() => run("Open Senior position", openSenior)}
              disabled={busy}
            />
            <ActionButton
              step="3"
              label="Push volatility (swap)"
              hint="Auto-approves, then swaps — click a few times"
              onClick={() => run("Swap", pushVolatility)}
              disabled={busy}
            />
          </div>
        )}

        {/* Status */}
        {status.kind !== "idle" && (
          <div className="mt-3 text-xs">
            {status.kind === "pending" && (
              <span className="text-zinc-400">⏳ {status.label} — confirm in your wallet…</span>
            )}
            {status.kind === "success" && (
              <span className="text-emerald-300">
                ✓ {status.label} confirmed ·{" "}
                <a
                  href={explorerTx(status.tx)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="underline-offset-2 hover:underline"
                >
                  {shortenHex(status.tx)}
                </a>
              </span>
            )}
            {status.kind === "error" && (
              <span className="text-rose-300">✕ {status.label}: {status.msg}</span>
            )}
          </div>
        )}

        {wallet.error && (
          <div className="mt-2 text-xs text-rose-300">{wallet.error}</div>
        )}

        <p className="mt-3 text-[11px] leading-relaxed text-zinc-600">
          After a few swaps, the Lasna controller reacts and calls back into the
          hook — this pool&apos;s badge above flips to CRISIS (fees up, coverage
          floored, Senior deposits halted) within ~15–30s. Needs Unichain Sepolia
          ETH for gas.
        </p>
      </div>
    </Card>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className="text-zinc-500">{label}</span>
      <span className="tabular font-medium text-zinc-200">{value}</span>
    </span>
  );
}

function ActionButton({
  step,
  label,
  hint,
  onClick,
  disabled,
}: {
  step: string;
  label: string;
  hint: string;
  onClick: () => void;
  disabled: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="flex flex-col items-start gap-0.5 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-left transition-colors hover:border-white/20 hover:bg-white/[0.05] disabled:cursor-not-allowed disabled:opacity-50"
    >
      <span className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
        Step {step}
      </span>
      <span className="text-sm font-medium text-zinc-100">{label}</span>
      <span className="text-[11px] text-zinc-600">{hint}</span>
    </button>
  );
}
