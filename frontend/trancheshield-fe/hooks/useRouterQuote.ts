"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { publicClient } from "@/lib/viem";
import { quoterAbi } from "@/lib/abi";
import {
  DYNAMIC_FEE_FLAG,
  HOOK_ADDRESS,
  POLL_INTERVAL_MS,
  QUOTER_ADDRESS,
  TICK_SPACING,
  TOKEN0,
  TOKEN1,
} from "@/lib/config";

const AMOUNT_IN = 10n ** 18n; // quote 1.0 token0 in

interface UseRouterQuote {
  amountIn: bigint;
  amountOut: bigint | null;
  gasEstimate: bigint | null;
  loading: boolean;
  error: string | null;
}

/**
 * Live quote from the official Uniswap v4 Quoter against the hook'd pool — proof
 * the hook is routable/quotable by standard infrastructure. `quoteExactInputSingle`
 * is nonpayable (reverts internally to return), so we eth_call it via simulateContract.
 */
export function useRouterQuote(): UseRouterQuote {
  const [amountOut, setAmountOut] = useState<bigint | null>(null);
  const [gasEstimate, setGasEstimate] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const alive = useRef(true);

  const read = useCallback(async () => {
    try {
      const { result } = await publicClient.simulateContract({
        address: QUOTER_ADDRESS,
        abi: quoterAbi,
        functionName: "quoteExactInputSingle",
        args: [
          {
            poolKey: {
              currency0: TOKEN0,
              currency1: TOKEN1,
              fee: DYNAMIC_FEE_FLAG,
              tickSpacing: TICK_SPACING,
              hooks: HOOK_ADDRESS,
            },
            zeroForOne: true,
            exactAmount: AMOUNT_IN,
            hookData: "0x",
          },
        ],
      });
      if (!alive.current) return;
      const [out, gas] = result as readonly [bigint, bigint];
      setAmountOut(out);
      setGasEstimate(gas);
      setError(null);
    } catch (e) {
      if (!alive.current) return;
      setError(e instanceof Error ? e.message : "Failed to fetch router quote");
    } finally {
      if (alive.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    alive.current = true;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    read();
    const id = setInterval(read, POLL_INTERVAL_MS * 3);
    return () => {
      alive.current = false;
      clearInterval(id);
    };
  }, [read]);

  return { amountIn: AMOUNT_IN, amountOut, gasEstimate, loading, error };
}
