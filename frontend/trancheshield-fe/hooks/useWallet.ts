"use client";

import { useCallback, useEffect, useState } from "react";
import { createWalletClient, custom, type Address, type WalletClient } from "viem";
import { unichainSepolia } from "@/lib/viem";
import { RPC_URL, UNICHAIN_SEPOLIA_ID } from "@/lib/config";

interface Eip1193Provider {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
}

declare global {
  interface Window {
    ethereum?: Eip1193Provider;
  }
}

export interface Wallet {
  account: Address | null;
  chainId: number | null;
  isConnected: boolean;
  isCorrectChain: boolean;
  hasWallet: boolean;
  connecting: boolean;
  error: string | null;
  connect: () => Promise<void>;
  switchToUnichain: () => Promise<void>;
  getClient: () => WalletClient | null;
}

export function useWallet(): Wallet {
  const [account, setAccount] = useState<Address | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasWallet, setHasWallet] = useState(false);

  useEffect(() => {
    // Set after mount (not a lazy initializer) to avoid an SSR hydration mismatch.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setHasWallet(typeof window !== "undefined" && !!window.ethereum);
  }, []);

  const getClient = useCallback((): WalletClient | null => {
    if (typeof window === "undefined" || !window.ethereum) return null;
    return createWalletClient({
      chain: unichainSepolia,
      transport: custom(window.ethereum),
    });
  }, []);

  const refreshChain = useCallback(async () => {
    if (!window.ethereum) return;
    const id = (await window.ethereum.request({ method: "eth_chainId" })) as string;
    setChainId(parseInt(id, 16));
  }, []);

  const connect = useCallback(async () => {
    setConnecting(true);
    setError(null);
    try {
      if (!window.ethereum) throw new Error("No injected wallet found — install MetaMask.");
      const accounts = (await window.ethereum.request({
        method: "eth_requestAccounts",
      })) as string[];
      setAccount((accounts[0] ?? null) as Address | null);
      await refreshChain();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Wallet connection failed");
    } finally {
      setConnecting(false);
    }
  }, [refreshChain]);

  const switchToUnichain = useCallback(async () => {
    if (!window.ethereum) return;
    const hexId = "0x" + UNICHAIN_SEPOLIA_ID.toString(16);
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: hexId }],
      });
    } catch (e) {
      if ((e as { code?: number })?.code === 4902) {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [
            {
              chainId: hexId,
              chainName: "Unichain Sepolia",
              nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
              rpcUrls: [RPC_URL],
              blockExplorerUrls: ["https://sepolia.uniscan.xyz"],
            },
          ],
        });
      } else {
        setError(e instanceof Error ? e.message : "Network switch failed");
      }
    }
    await refreshChain();
  }, [refreshChain]);

  useEffect(() => {
    const eth = window.ethereum;
    if (!eth?.on) return;
    const onAccounts = (...args: unknown[]) =>
      setAccount(((args[0] as string[])?.[0] ?? null) as Address | null);
    const onChain = (...args: unknown[]) =>
      setChainId(parseInt(args[0] as string, 16));
    eth.on("accountsChanged", onAccounts);
    eth.on("chainChanged", onChain);
    return () => {
      eth.removeListener?.("accountsChanged", onAccounts);
      eth.removeListener?.("chainChanged", onChain);
    };
  }, []);

  return {
    account,
    chainId,
    isConnected: !!account,
    isCorrectChain: chainId === UNICHAIN_SEPOLIA_ID,
    hasWallet,
    connecting,
    error,
    connect,
    switchToUnichain,
    getClient,
  };
}
