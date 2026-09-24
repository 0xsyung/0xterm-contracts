// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3FlashCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title ArbExecutor
 * @notice Permissionless single-transaction arbitrage between two venues,
 *         flash-funded from a third venue (poolC). Profit + tokenOther dust
 *         go to msg.sender. ERC20-only payout (no native handling).
 *
 *         Flash venue (poolC) is deliberately SEPARATE from the two leg venues
 *         (poolA/poolB): a Uniswap pool holds its `lock` through its own flash
 *         callback, so the legs must run against unlocked pools.
 *
 *         Factories are pinned at construction: at most ONE V2 pool can appear
 *         in a run (a V2 factory holds one pool per pair), so any other venue(s)
 *         must be V3 pools at distinct fee tiers of the pinned V3 factory.
 *
 *         Reverts (NO_PROFIT) if the realized profit is below minProfit — the
 *         whole tx unwinds, so no one-legged position is left behind.
 *
 *         Not a vault: no owner, no upgrade proxy, no skim, no inventory.
 *         Tokens accidentally sent here are only retrievable via a self-funded
 *         manufactured-profit run — for-profit extraction isn't profitable, so
 *         treat the executor as holding no balances outside of a run (v1).
 */
contract ArbExecutor {
    struct RunParams {
        address tokenStart;   // profit + flash denominated in this
        address tokenOther;
        address poolA;        // leg 1: tokenStart -> tokenOther
        address poolB;        // leg 2: tokenOther -> tokenStart
        address poolC;        // flash venue (must differ from A and B)
        uint24 feeA;          // V3 fee tier, or 0 when the leg is V2
        uint24 feeB;
        uint24 feeC;          // flash venue fee tier, or 0 when V2
        bool aIsV3;
        bool bIsV3;
        bool cIsV3;
        uint256 amountIn;     // flash / start size
        uint256 minProfit;    // require end-start >= minProfit in tokenStart
    }

    address public immutable v3Router;
    // Factories the legs/flash are validated against. Pinned at construction so
    // caller-supplied RunParams cannot point the executor at arbitrary pools.
    address public immutable v2Factory;
    address public immutable v3Factory;
    // address(this) while a run is in flight; address(0) otherwise.
    address private _active;

    constructor(address _v3Router, address _v2Factory, address _v3Factory) {
        require(_v3Router != address(0), "ZERO_ROUTER");
        require(_v2Factory != address(0), "ZERO_V2_FACTORY");
        require(_v3Factory != address(0), "ZERO_V3_FACTORY");
        v3Router = _v3Router;
        v2Factory = _v2Factory;
        v3Factory = _v3Factory;
    }

    /// @notice Atomic arb: flash on poolC, trade legs A/B, repay, profit to msg.sender.
    /// @return profit  net tokenStart gain (>= minProfit) sent to msg.sender
    /// @return dust    residual tokenOther sent to msg.sender
    function run(RunParams calldata p) external returns (uint256 profit, uint256 dust) {
        require(_active == address(0), "ACTIVE");
        _validate(p);
        address self = address(this);
        uint256 bal0 = IERC20(p.tokenStart).balanceOf(self);
        _active = self;

        if (p.cIsV3) {
            (address t0, address t1) = (IUniswapV3Pool(p.poolC).token0(), IUniswapV3Pool(p.poolC).token1());
            (uint256 amt0, uint256 amt1) = p.tokenStart == t0
                ? (p.amountIn, uint256(0))
                : (uint256(0), p.amountIn);
            IUniswapV3Pool(p.poolC).flash(self, amt0, amt1, abi.encode(p));
        } else {
            (address t0, ) = (IUniswapV2Pair(p.poolC).token0(), IUniswapV2Pair(p.poolC).token1());
            (uint256 amt0, uint256 amt1) = p.tokenStart == t0
                ? (p.amountIn, uint256(0)) // V2: borrow token0 as tokenStart
                : (uint256(0), p.amountIn); // borrow token1 as tokenStart
            IUniswapV2Pair(p.poolC).swap(amt0, amt1, self, abi.encode(p));
        }

        _active = address(0);
        profit = IERC20(p.tokenStart).balanceOf(self) - bal0;
        require(profit >= p.minProfit, "NO_PROFIT");
        dust = IERC20(p.tokenOther).balanceOf(self);
        if (profit > 0) IERC20(p.tokenStart).transfer(msg.sender, profit);
        if (dust > 0) IERC20(p.tokenOther).transfer(msg.sender, dust);
    }

    /// @dev UniV2 flash callback: legs A/B, then repay principal + 0.3% fee.
    function uniswapV2Call(address, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
        require(_active == address(this), "STRANGER");
        RunParams memory p = abi.decode(data, (RunParams));
        require(msg.sender == p.poolC && !p.cIsV3, "STRANGER");
        require((amount0Out > 0) != (amount1Out > 0), "BAD_FLASH");
        _validate(p); // forged data cannot point legs at non-factory pools
        _runLegs(p);
        // Repay principal + fee. The pair's K check requires 997*fee >= 3*X,
        // so the fee must round UP (floor loses the K check by <1 wei).
        uint256 borrowed = amount0Out > 0 ? amount0Out : amount1Out;
        uint256 repay = borrowed + (borrowed * 3 + 996) / 997;
        IERC20(p.tokenStart).transfer(p.poolC, repay);
    }

    /// @dev UniV3 flash callback: legs A/B, then repay principal + tier fee.
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        require(_active == address(this), "STRANGER");
        RunParams memory p = abi.decode(data, (RunParams));
        require(msg.sender == p.poolC && p.cIsV3, "STRANGER");
        _validate(p); // forged data cannot point legs at non-factory pools
        _runLegs(p);
        // Repay principal + fee. The borrowed tokenStart is either token0 or
        // token1 of poolC; fee for that side is fee0 or fee1.
        (address t0, ) = (IUniswapV3Pool(p.poolC).token0(), IUniswapV3Pool(p.poolC).token1());
        uint256 fee = p.tokenStart == t0 ? fee0 : fee1;
        IERC20(p.tokenStart).transfer(p.poolC, p.amountIn + fee);
    }

    function _runLegs(RunParams memory p) internal {
        if (p.aIsV3) {
            IERC20(p.tokenStart).approve(v3Router, p.amountIn);
            ISwapRouter(v3Router).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: p.tokenStart,
                    tokenOut: p.tokenOther,
                    fee: p.feeA,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: p.amountIn,
                    amountOutMinimum: 1,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            _swapV2(p.tokenStart, p.tokenOther, p.poolA, p.amountIn);
        }
        uint256 inOther = IERC20(p.tokenOther).balanceOf(address(this));
        if (p.bIsV3) {
            IERC20(p.tokenOther).approve(v3Router, inOther);
            ISwapRouter(v3Router).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: p.tokenOther,
                    tokenOut: p.tokenStart,
                    fee: p.feeB,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: inOther,
                    amountOutMinimum: 1,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            _swapV2(p.tokenOther, p.tokenStart, p.poolB, inOther);
        }
    }

    function _swapV2(address tokenIn, address, address pair, uint256 amountIn) internal {
        (address t0, address t1) = (IUniswapV2Pair(pair).token0(), IUniswapV2Pair(pair).token1());
        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();
        (bool inIs0, uint256 rIn, uint256 rOut) = tokenIn == t0 ? (true, r0, r1) : (false, r1, r0);
        uint256 amountOut = (amountIn * 997 * rOut) / (rIn * 1000 + amountIn * 997);
        // V2 pairs detect input by balance delta, not transferFrom — move the
        // tokens in (from this contract's own balance) before calling swap.
        IERC20(tokenIn).transfer(pair, amountIn);
        IUniswapV2Pair(pair).swap(inIs0 ? 0 : amountOut, inIs0 ? amountOut : 0, address(this), "");
    }

    function _validate(RunParams memory p) internal view {
        require(p.tokenStart != p.tokenOther, "SAME_TOKEN");
        require(p.amountIn > 0, "ZERO_AMOUNT");
        require(p.poolA != p.poolB && p.poolA != p.poolC && p.poolB != p.poolC, "DUP_POOL");
        if (p.aIsV3) {
            require(IUniswapV3Factory(v3Factory).getPool(p.tokenStart, p.tokenOther, p.feeA) == p.poolA, "BAD_POOL_A");
        } else {
            require(IUniswapV2Factory(v2Factory).getPair(p.tokenStart, p.tokenOther) == p.poolA, "BAD_POOL_A");
        }
        if (p.bIsV3) {
            require(IUniswapV3Factory(v3Factory).getPool(p.tokenOther, p.tokenStart, p.feeB) == p.poolB, "BAD_POOL_B");
        } else {
            require(IUniswapV2Factory(v2Factory).getPair(p.tokenOther, p.tokenStart) == p.poolB, "BAD_POOL_B");
        }
        if (p.cIsV3) {
            require(IUniswapV3Factory(v3Factory).getPool(p.tokenStart, p.tokenOther, p.feeC) == p.poolC, "BAD_POOL_C");
        } else {
            require(IUniswapV2Factory(v2Factory).getPair(p.tokenStart, p.tokenOther) == p.poolC, "BAD_POOL_C");
        }
    }
}
