// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Billboard.sol";

/**
 * @title UpgradeBillboard
 * @dev Soft ACK #139 slice 2: Billboard(proPass) upgrade.
 *      --sig "run(address,address)" <PROXY> <PRO_PASS>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract UpgradeBillboard is Script {
    function run(address proxyAddr, address proPass) external returns (address newImpl) {
        require(proPass != address(0), "UpgradeBillboard: zero proPass");
        vm.startBroadcast();

        Billboard newImplContract = new Billboard(proPass);
        Billboard(proxyAddr).upgradeToAndCall(address(newImplContract), "");

        vm.stopBroadcast();

        console.log("Billboard upgraded. Proxy:", proxyAddr);
        console.log("New implementation at:", address(newImplContract));
        console.log("ProPass:", address(Billboard(proxyAddr).proPass()));
        console.log("Owner:", Billboard(proxyAddr).owner());

        return address(newImplContract);
    }
}
