// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";

/// @title ILMath
/// @notice Impermanent-loss math for TrancheShield's full-range MVP.
/// @dev    Implements the formulas in PROJECT-v2.md §13. All values are denominated
///         in token1 (the higher-sorted pool currency). Concentrated-liquidity support
///         is explicit future work — see PROJECT-v2.md §26.
///
///         Price encoding: Uniswap v4 carries the pool price as `sqrtPriceX96`, a
///         Q64.96 fixed-point square root of token1/token0. The spot price P then is
///         `(sqrtPriceX96 / 2^96)^2`. Naively squaring overflows uint256 for prices
///         beyond a few thousand units, so this library applies the multiplication in
///         two FullMath.mulDiv steps to stay within uint256 across realistic ranges.
library ILMath {
    /// @notice Convert an `amount0` figure into its token1 equivalent at the supplied price.
    /// @dev    value1 = amount0 * (sqrtPriceX96/2^96)^2
    ///         Computed as mulDiv(mulDiv(amount0, sqrtP, Q96), sqrtP, Q96) to avoid
    ///         the intermediate uint256 overflow that direct squaring would cause.
    function token0ToToken1Value(uint256 amount0, uint160 sqrtPriceX96)
        internal
        pure
        returns (uint256 value1)
    {
        uint256 step1 = FullMath.mulDiv(amount0, uint256(sqrtPriceX96), FixedPoint96.Q96);
        value1 = FullMath.mulDiv(step1, uint256(sqrtPriceX96), FixedPoint96.Q96);
    }

    /// @notice HODL value: what the LP would be worth if they had simply held the entry
    ///         basket of tokens. PROJECT-v2.md §13:
    ///         HODL Value = amount0_entry * P_exit + amount1_entry
    function computeHodlValue(uint256 amount0Entry, uint256 amount1Entry, uint160 sqrtPriceX96Exit)
        internal
        pure
        returns (uint256 hodlValueToken1)
    {
        hodlValueToken1 = token0ToToken1Value(amount0Entry, sqrtPriceX96Exit) + amount1Entry;
    }

    /// @notice LP exit value: token1 value of what was actually withdrawn from the pool.
    ///         LP Exit Value = amount0_exit * P_exit + amount1_exit
    function computeLPExitValue(uint256 amount0Exit, uint256 amount1Exit, uint160 sqrtPriceX96Exit)
        internal
        pure
        returns (uint256 exitValueToken1)
    {
        exitValueToken1 = token0ToToken1Value(amount0Exit, sqrtPriceX96Exit) + amount1Exit;
    }

    /// @notice Impermanent-loss shortfall: how much the LP underperformed HODL.
    ///         Floored at zero — a positive LP outcome (exit > HODL) yields no payout.
    function computeILShortfall(uint256 hodlValueToken1, uint256 exitValueToken1)
        internal
        pure
        returns (uint256 shortfall)
    {
        if (exitValueToken1 >= hodlValueToken1) return 0;
        unchecked {
            shortfall = hodlValueToken1 - exitValueToken1;
        }
    }
}
