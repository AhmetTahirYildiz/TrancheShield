"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { parseEventLogs, type Hex } from "viem";
import { publicClient } from "@/lib/viem";
import { hookAbi } from "@/lib/abi";
import { SCENARIO_POOL_ID, SCENARIO_TX_HASH } from "@/lib/config";

export interface OnChainProof {
  ilShortfall: bigint;
  compensation: bigint;
  /** compensation / ilShortfall, in bps (5000 = 50%). */
  recoveryBps: number;
  txHash: Hex;
  blockNumber: bigint;
}

interface UseOnChainProof {
  proof: OnChainProof | null;
  loading: boolean;
  error: string | null;
}

/**
 * Reads the genuine PositionClosed event produced by script/RealComparison.s.sol:
 * a real Senior LP that took on-chain impermanent loss and received bounded
 * compensation from the Junior tranche. This is the dashboard's "not a model"
 * anchor — verifiable on the block explorer.
 *
 * It resolves the event from the known transaction RECEIPT (by hash) instead of
 * eth_getLogs over a fixed block range. The proof sits ~150k+ blocks back — past
 * the getLogs window many public RPCs serve, which is why a range query silently
 * returns empty — but getTransactionReceipt resolves a known hash regardless, so
 * the proof stays visible no matter how far the chain advances.
 */
export function useOnChainProof(): UseOnChainProof {
  const [proof, setProof] = useState<OnChainProof | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const alive = useRef(true);

  const load = useCallback(async () => {
    try {
      const receipt = await publicClient.getTransactionReceipt({
        hash: SCENARIO_TX_HASH,
      });

      const events = parseEventLogs({
        abi: hookAbi,
        eventName: "PositionClosed",
        logs: receipt.logs,
      });

      // The tx closes both tranches; the Senior close is the one carrying a
      // non-zero IL shortfall (Junior emits 0/0). Match the scenario pool too.
      const senior = events.find(
        (e) =>
          (e.args.poolId as Hex) === SCENARIO_POOL_ID &&
          (e.args.ilShortfall ?? 0n) > 0n,
      );

      if (!alive.current) return;

      if (!senior) {
        setProof(null);
        setError(null);
        return;
      }

      const ilShortfall = senior.args.ilShortfall ?? 0n;
      const compensation = senior.args.compensationPaid ?? 0n;
      setProof({
        ilShortfall,
        compensation,
        recoveryBps:
          ilShortfall > 0n ? Number((compensation * 10_000n) / ilShortfall) : 0,
        txHash: receipt.transactionHash,
        blockNumber: receipt.blockNumber,
      });
      setError(null);
    } catch (e) {
      if (!alive.current) return;
      setError(e instanceof Error ? e.message : "Failed to read on-chain proof");
    } finally {
      if (alive.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    alive.current = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
    return () => {
      alive.current = false;
    };
  }, [load]);

  return { proof, loading, error };
}
