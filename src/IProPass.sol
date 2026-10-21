// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IProPass
 * @dev Minimal surface for Soft ACK #139 onlyPro gates.
 *      Full ProPass lives at src/ProPass.sol (UUPS ERC-721).
 */
interface IProPass {
    function isPro(address account) external view returns (bool);
}
