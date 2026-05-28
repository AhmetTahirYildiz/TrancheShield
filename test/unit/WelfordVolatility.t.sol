// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {WelfordVolatility} from "../../src/libraries/WelfordVolatility.sol";

/// @dev Storage-backed harness so we can exercise the library's storage `update` path.
contract WelfordHarness {
    using WelfordVolatility for WelfordVolatility.VolatilityState;

    WelfordVolatility.VolatilityState internal s;

    function push(int256 x) external {
        s.update(x);
    }

    function count() external view returns (uint256) {
        return s.count;
    }

    function sum() external view returns (int256) {
        return s.sum;
    }

    function sumSq() external view returns (uint256) {
        return s.sumSq;
    }

    function variance() external view returns (uint256) {
        return WelfordVolatility.variance(s.count, s.sum, s.sumSq);
    }

    function stdev() external view returns (uint256) {
        return WelfordVolatility.stdev(s.count, s.sum, s.sumSq);
    }

    function stdevScaled(uint256 scale) external view returns (uint256) {
        return WelfordVolatility.stdevScaled(s.count, s.sum, s.sumSq, scale);
    }
}

contract WelfordVolatilityTest is Test {
    WelfordHarness internal h;

    function setUp() public {
        h = new WelfordHarness();
    }

    function _pushAll(int256[] memory xs) internal {
        for (uint256 i = 0; i < xs.length; i++) {
            h.push(xs[i]);
        }
    }

    // ---------------------------------------------------------------------
    // Edge cases
    // ---------------------------------------------------------------------

    function test_emptyWindow_isZero() public view {
        assertEq(h.count(), 0);
        assertEq(h.variance(), 0);
        assertEq(h.stdev(), 0);
    }

    function test_singleSample_varianceZero() public {
        h.push(42);
        assertEq(h.count(), 1);
        assertEq(h.variance(), 0, "sample variance undefined for n=1 -> 0");
        assertEq(h.stdev(), 0);
    }

    // ---------------------------------------------------------------------
    // Known reference values (computed by hand)
    // ---------------------------------------------------------------------

    function test_threeSamples_matchesReference() public {
        // [10,20,30]: mean 20, Σdev² = 200, sample var = 200/2 = 100, stdev = 10.
        h.push(10);
        h.push(20);
        h.push(30);
        assertEq(h.count(), 3);
        assertEq(h.sum(), 60);
        assertEq(h.sumSq(), 1400);
        assertEq(h.variance(), 100, "variance");
        assertEq(h.stdev(), 10, "stdev");
    }

    function test_fiveSamples_matchesReference() public {
        // [1,2,3,4,5]: sample var = 10/4 = 2 (integer), stdev = sqrt(2) = 1.
        for (int256 i = 1; i <= 5; i++) {
            h.push(i);
        }
        assertEq(h.count(), 5);
        assertEq(h.sum(), 15);
        assertEq(h.sumSq(), 55);
        assertEq(h.variance(), 2, "integer sample variance");
        assertEq(h.stdev(), 1);
    }

    function test_negativeTicks_handled() public {
        // [-10, 10]: mean 0, sumSq 200, var = (2*200 - 0)/(2*1) = 200, stdev = 14.
        h.push(-10);
        h.push(10);
        assertEq(h.sum(), 0);
        assertEq(h.sumSq(), 200);
        assertEq(h.variance(), 200);
        assertEq(h.stdev(), 14, "sqrt(200) floored");
    }

    // ---------------------------------------------------------------------
    // Window rotation
    // ---------------------------------------------------------------------

    function test_windowRotation_evictsOldest() public {
        // Fill with 1..20, then push 21..25. Window should hold 6..25.
        for (int256 i = 1; i <= 25; i++) {
            h.push(i);
        }
        assertEq(h.count(), 20, "count capped at WINDOW");

        // 6..25: sum = 310, sumSq = 5470, sample var = 35, stdev = 5.
        assertEq(h.sum(), 310, "sum after eviction");
        assertEq(h.sumSq(), 5470, "sumSq after eviction");
        assertEq(h.variance(), 35, "variance of 6..25");
        assertEq(h.stdev(), 5, "sqrt(35) floored");
    }

    function test_removalIsExact_matchesFreshWindow() public {
        // Push 1..30 into harness A (rotated): final window is 11..30.
        for (int256 i = 1; i <= 30; i++) {
            h.push(i);
        }

        // Build a fresh harness with exactly 11..30 and no rotation.
        WelfordHarness fresh = new WelfordHarness();
        for (int256 i = 11; i <= 30; i++) {
            fresh.push(i);
        }

        // Removal path must produce identical accumulators to a never-rotated window.
        assertEq(h.sum(), fresh.sum(), "sum exact after rotation");
        assertEq(h.sumSq(), fresh.sumSq(), "sumSq exact after rotation");
        assertEq(h.variance(), fresh.variance(), "variance exact after rotation");
    }

    // ---------------------------------------------------------------------
    // Scaling
    // ---------------------------------------------------------------------

    function test_stdevScaled_retainsPrecision() public {
        // [1,2,3,4,5]: variance = 2. Raw stdev = 1 (lossy). Scaled by 1000:
        // sqrt(2 * 1000^2) = sqrt(2_000_000) = 1414.
        for (int256 i = 1; i <= 5; i++) {
            h.push(i);
        }
        assertEq(h.stdev(), 1, "raw integer stdev is lossy");
        assertEq(h.stdevScaled(1000), 1414, "scaled stdev retains precision");
    }

    // ---------------------------------------------------------------------
    // Fuzz: variance is always non-negative and monotone-ish sanity
    // ---------------------------------------------------------------------

    function testFuzz_varianceNeverReverts(int24[20] calldata ticks) public {
        for (uint256 i = 0; i < 20; i++) {
            h.push(int256(ticks[i]));
        }
        // Must not revert; variance is well-defined and >= 0 by construction.
        uint256 v = h.variance();
        assertGe(v, 0);
    }
}
