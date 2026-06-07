import { createPublicClient, defineChain, http } from "viem";
import { RPC_URL, UNICHAIN_SEPOLIA_ID } from "./config";

export const unichainSepolia = defineChain({
  id: UNICHAIN_SEPOLIA_ID,
  name: "Unichain Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: {
    default: { name: "Uniscan", url: "https://sepolia.uniscan.xyz" },
  },
  testnet: true,
});

/** Read-only client. No wallet / signer — the dashboard never sends txs. */
export const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL),
});
