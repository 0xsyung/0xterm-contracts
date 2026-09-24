// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ArbExecutor} from "../src/ArbExecutor.sol";
import {MockToken} from "../src/MockToken.sol";
import {MockV2Pair} from "../src/mocks/MockV2Pair.sol";
import {MockV2Factory} from "../src/mocks/MockV2Factory.sol";
import {MockV3Pool} from "../src/mocks/MockV3Pool.sol";
import {MockV3Factory} from "../src/mocks/MockV3Factory.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";

/// Reentrant V2 pair: re-enters run() from swap() to test the _active guard.
contract ReentrantPool {
    ArbExecutor executor;
    address public token0;
    address public token1;

    constructor(address ex, address t0, address t1) {
        executor = ArbExecutor(ex);
        token0 = t0;
        token1 = t1;
    }

    function swap(uint256, uint256, address, bytes calldata data) external {
        executor.run(abi.decode(data, (ArbExecutor.RunParams)));
    }
}

contract ArbExecutorTest is Test {
    ArbExecutor arb;
    MockRouter router;
    // Factories are pinned at construction: a single V2 factory holds exactly one
    // pool per token pair, and a single V3 factory one pool per (pair, fee tier).
    // So at most ONE V2 venue can appear in a run (the other two must be V3 pools
    // at distinct fee tiers). An all-V2 3-venue arb is not representable — which
    // matches the real per-DEX factory layout.
    MockV2Factory v2F;
    MockV3Factory v3F;
    MockToken tokenS;
    MockToken tokenO;

    // The single V2 pool (can be one leg, or the flash venue — never both).
    MockV2Pair poolV2;

    // V3 leg/flash pools at distinct fee tiers.
    MockV3Pool poolA3; // tier 500
    MockV3Pool poolB3; // tier 3000
    MockV3Pool poolC3; // tier 10000

    uint24 constant FEE_B = 3000; // 0.3% tier
    uint24 constant FEE_C = 10000; // 1% tier (distinct from legs)
    uint24 constant FEE_A = 500; // 0.05% tier

    function setUp() public {
        v2F = new MockV2Factory();
        v3F = new MockV3Factory();
        router = new MockRouter(address(v3F));
        arb = new ArbExecutor(address(router), address(v2F), address(v3F));

        tokenS = new MockToken("Start", "SRT", 18, 0);
        tokenO = new MockToken("Other", "OTH", 18, 0);

        // The single V2 pool (S=1000, O=3000 -> price 3 O/S). Registered in the
        // pinned V2 factory so _validate accepts it.
        poolV2 = new MockV2Pair(address(tokenS), address(tokenO));
        v2F.setPair(address(tokenS), address(tokenO), address(poolV2));
        _seedV2(poolV2, 1000 ether, 3000 ether);

        // V3 pools: leg A S->O at 2.5 O/S (tier 500), leg B O->S at 0.5 S/O
        // (tier 3000), flash C at 1 ether price (tier 10000). All distinct tiers.
        poolA3 = _mkV3(address(tokenS), address(tokenO), 2.5 ether, FEE_A);
        poolB3 = _mkV3(address(tokenO), address(tokenS), 0.5 ether, FEE_B);
        poolC3 = new MockV3Pool(address(tokenS), address(tokenO), FEE_C, 1 ether);
        v3F.setPool(address(tokenS), address(tokenO), FEE_A, address(poolA3));
        v3F.setPool(address(tokenS), address(tokenO), FEE_B, address(poolB3));
        v3F.setPool(address(tokenS), address(tokenO), FEE_C, address(poolC3));

        _seedV3(poolA3, 1000 ether, 1000 ether);
        _seedV3(poolB3, 1000 ether, 1000 ether);
        _seedV3(poolC3, 1000 ether, 1000 ether);
    }

    // --- helpers ---

    /// Reserve of `token` in `pair` regardless of token0/token1 ordering.
    function _reserveOf(MockV2Pair pair, address token) internal view returns (uint256) {
        address t0 = address(pair.token0());
        address t1 = address(pair.token1());
        if (token == t0) return pair.reserve0();
        require(token == t1, "BAD_TOKEN");
        return pair.reserve1();
    }

    /// Seed a pair so the reserve for tokenS = aS and for tokenO = aO, whatever
    /// the pair's token0/token1 ordering.
    function _seedV2(MockV2Pair pair, uint256 aS, uint256 aO) internal {
        address t0 = address(pair.token0());
        address t1 = address(pair.token1());
        address a = t0 == address(tokenS) ? t0 : t1;
        (uint256 a0, uint256 a1) = t0 == address(tokenS) ? (aS, aO) : (aO, aS);
        MockToken(a).mint(address(this), a0);
        MockToken(a).approve(address(pair), a0);
        address b = a == t0 ? t1 : t0;
        MockToken(b).mint(address(this), a1);
        MockToken(b).approve(address(pair), a1);
        pair.seed(a, a0, a1);
    }

    function _mkV3(address tokenIn, address tokenOut, uint256 price, uint24 fee) internal returns (MockV3Pool) {
        bool zeroForOne = tokenIn < tokenOut;
        // price0 = token1-per-token0 so that swap yields `price` output per input.
        uint160 p0 = zeroForOne ? uint160(price) : uint160(1 ether * 1 ether / price);
        return new MockV3Pool(zeroForOne ? tokenIn : tokenOut, zeroForOne ? tokenOut : tokenIn, fee, p0);
    }

    function _seedV3(MockV3Pool pool, uint256 a0, uint256 a1) internal {
        tokenS.mint(address(this), a0);
        tokenS.approve(address(pool), a0);
        tokenO.mint(address(this), a1);
        tokenO.approve(address(pool), a1);
        pool.seed(address(tokenS), a0, a1);
    }

    /// Exact 0.3%-fee V2 output formula (mirrors _swapV2 / MockV2Pair).
    function _v2Out(uint256 amountIn, uint256 rIn, uint256 rOut) internal pure returns (uint256) {
        return (amountIn * 997 * rOut) / (rIn * 1000 + amountIn * 997);
    }

    function _repay(uint256 borrowed) internal pure returns (uint256) {
        return borrowed + (borrowed * 3 + 996) / 997;
    }

    // --- tests ---

    function test_V3Flash_V3V3_Profitable_PaysSender() public {
        uint256 amountIn = 10 ether;
        uint256 feeC = (amountIn * FEE_C) / 1e6;
        uint256 outA = (amountIn * 25) / 10; // price 2.5 O/S
        uint256 outB = (outA * 5) / 10; // price 0.5 S/O
        uint256 expectedProfit = outB - (amountIn + feeC);

        (uint256 profit, uint256 dust) = arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: address(poolB3),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: amountIn,
                minProfit: 0
            })
        );

        assertEq(profit, expectedProfit, "profit");
        assertEq(dust, 0, "dust");
        assertEq(tokenS.balanceOf(address(this)), expectedProfit, "sender S");
        assertEq(tokenO.balanceOf(address(this)), 0, "sender O");
        assertEq(tokenS.balanceOf(address(arb)), 0, "executor S empty");
        assertEq(tokenO.balanceOf(address(arb)), 0, "executor O empty");
    }

    function test_V2Flash_V3V3_Profitable_PaysSender() public {
        uint256 amountIn = 10 ether;
        uint256 outA = (amountIn * 25) / 10; // V3 leg A, 2.5 O/S
        uint256 outB = (outA * 5) / 10; // V3 leg B, 0.5 S/O
        uint256 repay = _repay(amountIn); // V2 flash fee (ceil 0.3%)
        uint256 expectedProfit = outB - repay;

        (uint256 profit, uint256 dust) = arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: address(poolB3),
                poolC: address(poolV2),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: 0,
                aIsV3: true,
                bIsV3: true,
                cIsV3: false,
                amountIn: amountIn,
                minProfit: 0
            })
        );

        assertEq(profit, expectedProfit, "profit");
        assertEq(dust, 0, "dust");
        assertEq(tokenS.balanceOf(address(this)), expectedProfit, "sender S");
        assertEq(tokenO.balanceOf(address(this)), 0, "sender O");
        assertEq(tokenS.balanceOf(address(arb)), 0, "executor S empty");
        assertEq(tokenO.balanceOf(address(arb)), 0, "executor O empty");
        // V2 flash venue grew only by the 0.3% fee (ceil).
        assertEq(_reserveOf(poolV2, address(tokenS)), 1000 ether + (amountIn * 3 + 996) / 997, "poolV2 S");
        assertEq(_reserveOf(poolV2, address(tokenO)), 3000 ether, "poolV2 O");
    }

    function test_V3Flash_V2V3_Profitable_PaysSender() public {
        uint256 amountIn = 10 ether;
        uint256 feeC = (amountIn * FEE_C) / 1e6;
        uint256 outA = _v2Out(amountIn, 1000 ether, 3000 ether); // V2 leg A (3 O/S)
        uint256 outB = (outA * 5) / 10; // V3 leg B (0.5 S/O)
        uint256 expectedProfit = outB - (amountIn + feeC);

        // Leg A = V2 pool, leg B = poolB3 (V3), flash = poolC3 (V3).
        ArbExecutor.RunParams memory p = ArbExecutor.RunParams({
            tokenStart: address(tokenS),
            tokenOther: address(tokenO),
            poolA: address(poolV2),
            poolB: address(poolB3),
            poolC: address(poolC3),
            feeA: 0,
            feeB: FEE_B,
            feeC: FEE_C,
            aIsV3: false,
            bIsV3: true,
            cIsV3: true,
            amountIn: amountIn,
            minProfit: 0
        });
        (uint256 profit, uint256 dust) = arb.run(p);

        assertEq(profit, expectedProfit, "profit");
        assertEq(dust, 0, "dust");
        assertEq(tokenS.balanceOf(address(this)), expectedProfit, "sender S");
        assertEq(tokenS.balanceOf(address(arb)), 0, "executor S empty");
        // V2 leg moved by the traded amounts.
        assertEq(_reserveOf(poolV2, address(tokenS)), 1000 ether + amountIn, "poolV2 S");
        assertEq(_reserveOf(poolV2, address(tokenO)), 3000 ether - outA, "poolV2 O");
    }

    function test_V3Flash_MinProfitExact_Succeeds() public {
        uint256 amountIn = 10 ether;
        uint256 feeC = (amountIn * FEE_C) / 1e6;
        uint256 outA = (amountIn * 25) / 10;
        uint256 outB = (outA * 5) / 10;
        uint256 expectedProfit = outB - (amountIn + feeC);

        (uint256 profit,) = arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: address(poolB3),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: amountIn,
                minProfit: expectedProfit
            })
        );
        assertEq(profit, expectedProfit);
    }

    function test_MinProfitTooHigh_NoProfit_RevertsAtomic() public {
        uint256 amountIn = 10 ether;
        uint256 feeC = (amountIn * FEE_C) / 1e6;
        uint256 outA = (amountIn * 25) / 10;
        uint256 outB = (outA * 5) / 10;
        uint256 expectedProfit = outB - (amountIn + feeC);

        uint256 sA = tokenS.balanceOf(address(poolA3));
        uint256 oA = tokenO.balanceOf(address(poolA3));
        uint256 sB = tokenS.balanceOf(address(poolB3));
        uint256 oB = tokenO.balanceOf(address(poolB3));
        uint256 sC = tokenS.balanceOf(address(poolC3));
        uint256 oC = tokenO.balanceOf(address(poolC3));

        vm.expectRevert(bytes("NO_PROFIT"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: address(poolB3),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: amountIn,
                minProfit: expectedProfit + 1
            })
        );

        assertEq(tokenS.balanceOf(address(poolA3)), sA, "poolA S unchanged");
        assertEq(tokenO.balanceOf(address(poolA3)), oA, "poolA O unchanged");
        assertEq(tokenS.balanceOf(address(poolB3)), sB, "poolB S unchanged");
        assertEq(tokenO.balanceOf(address(poolB3)), oB, "poolB O unchanged");
        assertEq(tokenS.balanceOf(address(poolC3)), sC, "poolC S unchanged");
        assertEq(tokenO.balanceOf(address(poolC3)), oC, "poolC O unchanged");
    }

    function test_EqualPrices_RevertsAtomic() public {
        // Both legs at 1:1 -> round trip loses the flash fee, cannot repay.
        MockV3Pool pA = _mkV3(address(tokenS), address(tokenO), 1 ether, FEE_A);
        MockV3Pool pB = _mkV3(address(tokenO), address(tokenS), 1 ether, FEE_B);
        v3F.setPool(address(tokenS), address(tokenO), FEE_A, address(pA));
        v3F.setPool(address(tokenS), address(tokenO), FEE_B, address(pB));
        _seedV3(pA, 1000 ether, 1000 ether);
        _seedV3(pB, 1000 ether, 1000 ether);

        uint256 sA = tokenS.balanceOf(address(pA));
        uint256 oA = tokenO.balanceOf(address(pA));
        uint256 sB = tokenS.balanceOf(address(pB));
        uint256 oB = tokenO.balanceOf(address(pB));
        uint256 sC = tokenS.balanceOf(address(poolC3));
        uint256 oC = tokenO.balanceOf(address(poolC3));

        vm.expectRevert();
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(pA),
                poolB: address(pB),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: 10 ether,
                minProfit: 0
            })
        );

        assertEq(tokenS.balanceOf(address(pA)), sA);
        assertEq(tokenO.balanceOf(address(pA)), oA);
        assertEq(tokenS.balanceOf(address(pB)), sB);
        assertEq(tokenO.balanceOf(address(pB)), oB);
        assertEq(tokenS.balanceOf(address(poolC3)), sC);
        assertEq(tokenO.balanceOf(address(poolC3)), oC);
    }

    function test_BadPool_Reverts() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert(bytes("BAD_POOL_A"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: stranger,
                poolB: address(poolB3),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: 10 ether,
                minProfit: 0
            })
        );

        vm.expectRevert(bytes("BAD_POOL_B"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: stranger,
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: 10 ether,
                minProfit: 0
            })
        );

        vm.expectRevert(bytes("BAD_POOL_C"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: address(poolB3),
                poolC: stranger,
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: 0,
                aIsV3: true,
                bIsV3: true,
                cIsV3: false,
                amountIn: 10 ether,
                minProfit: 0
            })
        );

        // A V2 pool passed as V3 cannot be validated against the pinned v3Factory.
        vm.expectRevert(bytes("BAD_POOL_A"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolV2),
                poolB: address(poolB3),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: 10 ether,
                minProfit: 0
            })
        );
    }

    function test_StrangerCallback_Reverts() public {
        vm.expectRevert(bytes("STRANGER"));
        arb.uniswapV2Call(address(0), 1, 0, "");
        vm.expectRevert(bytes("STRANGER"));
        arb.uniswapV3FlashCallback(0, 0, "");
    }

    function test_ReentrantRun_RevertsActive() public {
        // Reentrant pool must be the single V2 venue (legs go to V3 pools).
        ReentrantPool re = new ReentrantPool(address(arb), address(tokenS), address(tokenO));
        v2F.setPair(address(tokenS), address(tokenO), address(re));
        vm.expectRevert(bytes("ACTIVE"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(poolA3),
                poolB: address(poolB3),
                poolC: address(re),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: 0,
                aIsV3: true,
                bIsV3: true,
                cIsV3: false,
                amountIn: 10 ether,
                minProfit: 0
            })
        );
    }

    function test_PinnedFactory_FakePoolNotAccepted() public {
        // The BLOCKER regression: a caller cannot supply a fake factory to route
        // legs through attacker-owned pools. The executor only accepts pools that
        // resolve from its pinned v2Factory/v3Factory.
        MockV3Factory fakeFactory = new MockV3Factory();
        MockV3Pool fakePool = new MockV3Pool(address(tokenS), address(tokenO), FEE_A, 2.5 ether);
        _seedV3(fakePool, 1000 ether, 1000 ether);
        fakeFactory.setPool(address(tokenS), address(tokenO), FEE_A, address(fakePool));

        // Even though a fake factory resolves the pool, the executor validates
        // against ITS pinned v3Factory -> the pool isn't registered there.
        vm.expectRevert(bytes("BAD_POOL_A"));
        arb.run(
            ArbExecutor.RunParams({
                tokenStart: address(tokenS),
                tokenOther: address(tokenO),
                poolA: address(fakePool),
                poolB: address(poolB3),
                poolC: address(poolC3),
                feeA: FEE_A,
                feeB: FEE_B,
                feeC: FEE_C,
                aIsV3: true,
                bIsV3: true,
                cIsV3: true,
                amountIn: 10 ether,
                minProfit: 0
            })
        );
    }
}
