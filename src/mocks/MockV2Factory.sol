// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockV2Factory
 * @dev Registry-only mock of IUniswapV2Factory.getPair. Order-insensitive.
 */
contract MockV2Factory {
    mapping(address => mapping(address => address)) public getPair;

    function setPair(address tokenA, address tokenB, address pair) external {
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}
