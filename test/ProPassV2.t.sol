// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProPass} from "../src/ProPass.sol";

/**
 * @dev Test-only "v2" of ProPass, used to prove UUPS upgrades keep membership.
 *      MUST preserve ProPass storage layout and only ADD new state at the end.
 *      Do not use in production.
 */
contract ProPassV2 is ProPass {
    uint256 public versionTag;

    function setVersionTag(uint256 x) external {
        versionTag = x;
    }
}
