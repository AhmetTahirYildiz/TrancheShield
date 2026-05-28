// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title WelfordVolatility
/// @notice Rolling-window volatility for the ReactiveRiskController (PROJECT-v2.md §9.2).
/// @dev    The controller pushes one tick sample per observed swap and reads back the
///         standard deviation to derive a volatility score. The window is bounded to
///         `WINDOW` samples; when full, the oldest sample is evicted before the newest
///         is admitted, all in O(1).
///
///         Implementation note — Welford vs. sum/sum-of-squares:
///         The canonical Welford online algorithm keeps a running `mean` and `M2`. Its
///         add step is numerically stable in floating point, but the *removal* step
///         required for a sliding window accumulates rounding drift in integer
///         arithmetic (the mean is fractional and must be re-rounded every add/remove).
///         We instead keep running `sum` and `sumSq`, which is algebraically identical
///         to the two-pass variance Welford approximates, and is **exact** in integer
///         arithmetic over our bounded tick domain (int24, |tick| <= 887_272). For a
///         20-sample window: sumSq <= 20 * 887_272^2 ≈ 1.6e13 and sum^2 <= (20*887_272)^2
///         ≈ 3.1e14 — both comfortably inside uint256. This trades the textbook name for
///         exactness and lets the unit tests assert equality rather than tolerance.
library WelfordVolatility {
    /// @notice Maximum number of samples retained in the rolling window.
    uint256 internal constant WINDOW = 20;

    /// @notice Rolling-window accumulator. Lives in the RVM-side state of the RSC.
    struct VolatilityState {
        int256[20] window; // ring buffer of raw tick samples
        uint256 index;     // next write position; when full this slot holds the oldest sample
        uint256 count;     // number of valid samples currently in the window (<= WINDOW)
        int256 sum;        // running sum of samples in the window
        uint256 sumSq;     // running sum of squared samples in the window
    }

    /// @notice Admit a new tick sample, evicting the oldest when the window is full.
    /// @param s The volatility accumulator (storage).
    /// @param x The new tick sample (a Uniswap v4 tick, signed).
    function update(VolatilityState storage s, int256 x) internal {
        if (s.count == WINDOW) {
            // Ring is full: the slot at `index` currently holds the oldest sample.
            int256 old = s.window[s.index];
            s.sum -= old;
            s.sumSq -= uint256(old * old);
        } else {
            s.count += 1;
        }

        s.window[s.index] = x;
        s.sum += x;
        s.sumSq += uint256(x * x);

        unchecked {
            s.index = (s.index + 1) % WINDOW;
        }
    }

    /// @notice Sample variance (Bessel-corrected, count-1 denominator) of the window.
    /// @dev    Returns 0 for fewer than two samples. Result is in tick² units.
    ///         var = (count·sumSq − sum²) / (count·(count−1)).
    function variance(uint256 count, int256 sum, uint256 sumSq) internal pure returns (uint256) {
        if (count < 2) return 0;

        // count·sumSq − sum² is the (count × Σ(xᵢ−mean)²) numerator and is provably
        // non-negative by Cauchy–Schwarz; the guard is belt-and-suspenders.
        uint256 sumSquared = uint256(sum * sum);
        uint256 lhs = count * sumSq;
        if (lhs <= sumSquared) return 0;

        return (lhs - sumSquared) / (count * (count - 1));
    }

    /// @notice Standard deviation of the window, in tick units (integer sqrt of variance).
    function stdev(uint256 count, int256 sum, uint256 sumSq) internal pure returns (uint256) {
        return sqrt(variance(count, sum, sumSq));
    }

    /// @notice Standard deviation pre-multiplied by `scale`, computed as
    ///         sqrt(variance · scale²) to retain precision lost by integer sqrt.
    /// @dev    The controller uses this so a small raw stdev still produces a meaningful
    ///         volatility score against the LOW/MEDIUM/HIGH/CRISIS thresholds.
    function stdevScaled(uint256 count, int256 sum, uint256 sumSq, uint256 scale)
        internal
        pure
        returns (uint256)
    {
        uint256 v = variance(count, sum, sumSq);
        return sqrt(v * scale * scale);
    }

    /// @notice Babylonian integer square root.
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
