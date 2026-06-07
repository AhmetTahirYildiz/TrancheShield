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
