"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getAbiItem, type Hex } from "viem";
import { publicClient } from "@/lib/viem";
import { hookAbi } from "@/lib/abi";
import {
  HOOK_ADDRESS,
  SCENARIO_FROM_BLOCK,
  SCENARIO_POOL_ID,
  SCENARIO_TO_BLOCK,
} from "@/lib/config";

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

const positionClosedEvent = getAbiItem({ abi: hookAbi, name: "PositionClosed" });

/**
 * Reads the genuine PositionClosed event produced by script/RealComparison.s.sol:
 * a real Senior LP that took on-chain impermanent loss and received bounded
 * compensation from the Junior tranche. This is the dashboard's "not a model"
 * anchor — verifiable on the block explorer.
 */
export function useOnChainProof(): UseOnChainProof {
  const [proof, setProof] = useState<OnChainProof | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const alive = useRef(true);

  const load = useCallback(async () => {
    try {
      const logs = await publicClient.getLogs({
        address: HOOK_ADDRESS,
        event: positionClosedEvent,
        args: { poolId: SCENARIO_POOL_ID },
        fromBlock: SCENARIO_FROM_BLOCK,
        toBlock: SCENARIO_TO_BLOCK,
      });

      // The Senior close is the one with a non-zero IL; pick the latest.
      const senior = logs
        .filter((l) => (l.args.ilShortfall ?? 0n) > 0n)
        .sort((a, b) => Number((b.blockNumber ?? 0n) - (a.blockNumber ?? 0n)))[0];

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
          ilShortfall > 0n
            ? Number((compensation * 10_000n) / ilShortfall)
            : 0,
        txHash: senior.transactionHash ?? ("0x" as Hex),
        blockNumber: senior.blockNumber ?? 0n,
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
