// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import { MockV3Factory } from "./MockV3Factory.sol";
import { MockV3Pool } from "./MockV3Pool.sol";

/**
 * @title MockRouter
 * @dev ISwapRouter.exactInputSingle mock: pulls input from msg.sender (like the
 *      real router), routes through a MockV3Pool resolved from the factory.
 *      Struct mirrors the real ISwapRouter.ExactInputSingleParams field order.
 */
contract MockRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    MockV3Factory public immutable factory;

    constructor(address _factory) {
        factory = MockV3Factory(_factory);
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut) {
        require(params.deadline >= block.timestamp, "EXPIRED");
        address pool = factory.getPool(params.tokenIn, params.tokenOut, params.fee);
        require(pool != address(0), "NO_POOL");
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IERC20(params.tokenIn).approve(pool, params.amountIn);
        (int256 amount0, int256 amount1) = MockV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(params.amountIn),
            params.sqrtPriceLimitX96,
            ""
        );
        amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);
        require(amountOut >= params.amountOutMinimum, "SLIPPAGE");
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
    }
}
