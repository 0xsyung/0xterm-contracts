// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@uniswap/v2-core/contracts/interfaces/IERC20.sol";

/**
 * @title MockV2Pair
 * @dev Minimal Uniswap V2-style pair with constant-product reserves and a
 *      0.3% fee, supporting flash swaps via the uniswapV2Call callback.
 *      Input tokens are detected by balance delta (like the real pair) — the
 *      caller must transfer input in before calling swap().
 */
contract MockV2Pair {
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint256 public reserve0;
    uint256 public reserve1;

    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (uint112(reserve0), uint112(reserve1), uint32(block.timestamp));
    }

    /// @dev Add liquidity (no LP shares — mock). Mints nothing; used by tests.
    function seed(address t, uint256 a0, uint256 a1) external {
        require(t == address(token0) || t == address(token1), "BAD_TOKEN");
        if (t == address(token0)) {
            IERC20(token0).transferFrom(msg.sender, address(this), a0);
            IERC20(token1).transferFrom(msg.sender, address(this), a1);
            reserve0 += a0;
            reserve1 += a1;
        } else {
            IERC20(token1).transferFrom(msg.sender, address(this), a0);
            IERC20(token0).transferFrom(msg.sender, address(this), a1);
            reserve1 += a0;
            reserve0 += a1;
        }
        emit Sync(uint112(reserve0), uint112(reserve1));
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < reserve0 && amount1Out < reserve1, "INSUFFICIENT_LIQUIDITY");
        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);

        if (data.length > 0) {
            IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        }

        // Balance-delta input detection + K check with 0.3% fee.
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT_AMOUNT");
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        require(balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1_000_000, "K");
        reserve0 = balance0;
        reserve1 = balance1;
        emit Sync(uint112(reserve0), uint112(reserve1));
    }
}

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
