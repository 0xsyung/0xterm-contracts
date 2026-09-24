// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@uniswap/v2-core/contracts/interfaces/IERC20.sol";

/**
 * @title MockV3Pool
 * @dev Minimal Uniswap V3-style pool: fixed-price constant-liquidity swaps
 *      plus flash with tier-fee repayment. Mirrors the real pool's flash math:
 *      balance after flash must be >= balanceBefore + fee.
 */
contract MockV3Pool {
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint24 public immutable fee;
    uint160 internal _price0; // token1 per token0 in 1e18 units (price0 = price1 ... see slot0)
    uint128 internal _liquidity;

    event Sync(uint160 price0);

    /// @dev price passed in = token1-per-token0 in 1e18 units (0.5 -> 5e17).
    constructor(address _token0, address _token1, uint24 _fee, uint160 price) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        fee = _fee;
        _price0 = price;
        _liquidity = 1;
    }

    function setPrice(uint160 price) external {
        _price0 = price;
        emit Sync(price);
    }

    function slot0()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)
    {
        return (_price0, 0, 0, 0, 0, 0, true);
    }

    function liquidity() external view returns (uint128) {
        return _liquidity;
    }

    /// @dev Add inventory directly (no LP shares — mock). Used by tests.
    function seed(address t, uint256 a0, uint256 a1) external {
        require(t == address(token0) || t == address(token1), "BAD_TOKEN");
        if (t == address(token0)) {
            token0.transferFrom(msg.sender, address(this), a0);
            token1.transferFrom(msg.sender, address(this), a1);
        } else {
            token1.transferFrom(msg.sender, address(this), a0);
            token0.transferFrom(msg.sender, address(this), a1);
        }
    }

    /// @dev Fixed-price swap: output = amountIn * price (token1 per token0).
    ///      Returns signed deltas like the real pool: +delta = pool received,
    ///      -delta = pool sent out.
    function swap(
        address,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata
    ) external returns (int256, int256) {
        require(amountSpecified > 0, "MOCK_NEGATIVE");
        uint256 amountIn = uint256(amountSpecified);
        uint256 amountOut = zeroForOne ? (amountIn * uint256(_price0)) / 1e18 : (amountIn * 1e18) / uint256(_price0);
        IERC20(zeroForOne ? token0 : token1).transferFrom(msg.sender, address(this), amountIn);
        IERC20(zeroForOne ? token1 : token0).transfer(msg.sender, amountOut);
        return zeroForOne
            ? (amountSpecified, -int256(amountOut))
            : (-int256(amountOut), amountSpecified);
    }

    /// @dev Flash with tier fee: caller repays principal + fee (fee = 1/price...):
    ///      each side's fee is amountIn * fee / 1e6 (fee is in 1e6 units).
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external {
        uint256 bal0Before = token0.balanceOf(address(this));
        uint256 bal1Before = token1.balanceOf(address(this));
        if (amount0 > 0) token0.transfer(recipient, amount0);
        if (amount1 > 0) token1.transfer(recipient, amount1);
        uint256 fee0 = (amount0 * uint256(fee)) / 1e6;
        uint256 fee1 = (amount1 * uint256(fee)) / 1e6;
        if (data.length > 0) {
            IUniswapV3FlashCallback(recipient).uniswapV3FlashCallback(fee0, fee1, data);
        }
        require(token0.balanceOf(address(this)) >= bal0Before + fee0, "MOCK_F0");
        require(token1.balanceOf(address(this)) >= bal1Before + fee1, "MOCK_F1");
    }
}

interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}
