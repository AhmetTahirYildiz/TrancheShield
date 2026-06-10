"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { Hex } from "viem";
import { publicClient } from "@/lib/viem";
import { hookAbi } from "@/lib/abi";
import { HOOK_ADDRESS, POOL_ID, POLL_INTERVAL_MS } from "@/lib/config";

export interface RiskState {
  mode: number;
  volatilityScore: bigint;
  reserveRatio: bigint;
  seniorLiability: bigint;
  juniorCollateral: bigint;
  feeMultiplierBps: bigint;
  coverageRatioBps: bigint;
  seniorDepositsEnabled: boolean;
  lastRiskUpdate: bigint;
}

interface UsePoolRiskState {
  state: RiskState | null;
  loading: boolean;
  error: string | null;
  /** Wall-clock time of the last successful read. */
  fetchedAt: number | null;
  refetch: () => void;
}

/**
 * Polls TrancheShieldHook.getPoolRiskState(poolId) on an interval. This is the
 * dashboard's live heartbeat — a single eth_call that always works regardless of
 * how old the demo events are.
 */
export function usePoolRiskState(poolId: Hex = POOL_ID): UsePoolRiskState {
  const [state, setState] = useState<RiskState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [fetchedAt, setFetchedAt] = useState<number | null>(null);
  const alive = useRef(true);

  const read = useCallback(async () => {
    try {
      const result = (await publicClient.readContract({
        address: HOOK_ADDRESS,
        abi: hookAbi,
        functionName: "getPoolRiskState",
        args: [poolId],
      })) as RiskState;
      if (!alive.current) return;
      setState(result);
      setFetchedAt(Date.now());
      setError(null);
    } catch (e) {
      if (!alive.current) return;
      setError(e instanceof Error ? e.message : "Failed to read pool state");
    } finally {
      if (alive.current) setLoading(false);
    }
  }, [poolId]);

  useEffect(() => {
    alive.current = true;
    // Polling an external system (the RPC); setState only runs after `await`.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    read();
    const id = setInterval(read, POLL_INTERVAL_MS);
    return () => {
      alive.current = false;
      clearInterval(id);
    };
  }, [read]);

  return { state, loading, error, fetchedAt, refetch: read };
}
