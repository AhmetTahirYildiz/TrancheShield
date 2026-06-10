/**
 * Minimal hand-written ABIs — only the surface the dashboard reads. Kept narrow
 * (instead of dumping the full Foundry artifact) so the types stay legible.
 * Signatures mirror src/interfaces/ITrancheShieldHook.sol and
 * src/reactive/CallbackReceiver.sol. `PoolId` is a bytes32 value type on-chain.
 */

export const hookAbi = [
  {
    type: "function",
    name: "getPoolRiskState",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        name: "",
        components: [
          { name: "mode", type: "uint8" },
          { name: "volatilityScore", type: "uint256" },
          { name: "reserveRatio", type: "uint256" },
          { name: "seniorLiability", type: "uint256" },
          { name: "juniorCollateral", type: "uint256" },
          { name: "feeMultiplierBps", type: "uint256" },
          { name: "coverageRatioBps", type: "uint256" },
          { name: "seniorDepositsEnabled", type: "bool" },
          { name: "lastRiskUpdate", type: "uint256" },
        ],
      },
    ],
  },
  {
    type: "event",
    name: "SwapRiskObserved",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "tickBefore", type: "int24", indexed: false },
      { name: "tickAfter", type: "int24", indexed: false },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "RiskModeChanged",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "oldMode", type: "uint8", indexed: false },
      { name: "newMode", type: "uint8", indexed: false },
    ],
  },
  {
    type: "event",
    name: "FeeMultiplierUpdated",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "oldBps", type: "uint256", indexed: false },
      { name: "newBps", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CoverageRatioUpdated",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "oldBps", type: "uint256", indexed: false },
      { name: "newBps", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SeniorDepositStatusChanged",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "enabled", type: "bool", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SeniorWithdrawalRequested",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "liquidity", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "PositionClosed",
    inputs: [
      { name: "positionKey", type: "bytes32", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "ilShortfall", type: "uint256", indexed: false },
      { name: "compensationPaid", type: "uint256", indexed: false },
    ],
  },
] as const;

/** Official Uniswap v4 Quoter (lens). `quoteExactInputSingle` is nonpayable
 *  (it reverts the unlock internally to return the quote) — call it via eth_call. */
export const quoterAbi = [
  {
    type: "function",
    name: "quoteExactInputSingle",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          {
            name: "poolKey",
            type: "tuple",
            components: [
              { name: "currency0", type: "address" },
              { name: "currency1", type: "address" },
              { name: "fee", type: "uint24" },
              { name: "tickSpacing", type: "int24" },
              { name: "hooks", type: "address" },
            ],
          },
          { name: "zeroForOne", type: "bool" },
          { name: "exactAmount", type: "uint128" },
          { name: "hookData", type: "bytes" },
        ],
      },
    ],
    outputs: [
      { name: "amountOut", type: "uint256" },
      { name: "gasEstimate", type: "uint256" },
    ],
  },
] as const;

/** MockERC20 (solmate) — public mint, plus the ERC20 bits the interactive flow needs. */
export const mockErc20Abi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

const POOL_KEY_COMPONENTS = [
  { name: "currency0", type: "address" },
  { name: "currency1", type: "address" },
  { name: "fee", type: "uint24" },
  { name: "tickSpacing", type: "int24" },
  { name: "hooks", type: "address" },
] as const;

/** v4 PoolModifyLiquidityTest router — add/remove liquidity with hookData. */
export const modifyRouterAbi = [
  {
    type: "function",
    name: "modifyLiquidity",
    stateMutability: "payable",
    inputs: [
      { name: "key", type: "tuple", components: POOL_KEY_COMPONENTS },
      {
        name: "params",
        type: "tuple",
        components: [
          { name: "tickLower", type: "int24" },
          { name: "tickUpper", type: "int24" },
          { name: "liquidityDelta", type: "int256" },
          { name: "salt", type: "bytes32" },
        ],
      },
      { name: "hookData", type: "bytes" },
    ],
    outputs: [{ name: "delta", type: "int256" }],
  },
] as const;

/** v4 PoolSwapTest router — single-pool swap with hookData. */
export const swapRouterAbi = [
  {
    type: "function",
    name: "swap",
    stateMutability: "payable",
    inputs: [
      { name: "key", type: "tuple", components: POOL_KEY_COMPONENTS },
      {
        name: "params",
        type: "tuple",
        components: [
          { name: "zeroForOne", type: "bool" },
          { name: "amountSpecified", type: "int256" },
          { name: "sqrtPriceLimitX96", type: "uint160" },
        ],
      },
      {
        name: "testSettings",
        type: "tuple",
        components: [
          { name: "takeClaims", type: "bool" },
          { name: "settleUsingBurn", type: "bool" },
        ],
      },
      { name: "hookData", type: "bytes" },
    ],
    outputs: [{ name: "delta", type: "int256" }],
  },
] as const;

export const receiverAbi = [
  {
    type: "event",
    name: "RiskParameterUpdated",
    inputs: [
      { name: "parameter", type: "bytes32", indexed: true },
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "value", type: "uint256", indexed: false },
    ],
  },
] as const;
