// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EnsRegistry.sol";

/**
 * @title UpgradeENS
 * @dev Soft ACK #139 slice 2: EnsRegistry(proPass) upgrade.
 *      --sig "run(address,address)" <PROXY> <PRO_PASS>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract UpgradeENS is Script {
    function run(address proxyAddr, address proPass) external returns (address newImpl) {
        require(proPass != address(0), "UpgradeENS: zero proPass");
        vm.startBroadcast();

        EnsRegistry newImplContract = new EnsRegistry(proPass);
        EnsRegistry(proxyAddr).upgradeToAndCall(address(newImplContract), "");

        vm.stopBroadcast();

        console.log("ENS upgraded. Proxy:", proxyAddr);
        console.log("New implementation at:", address(newImplContract));
        console.log("ProPass:", address(EnsRegistry(proxyAddr).proPass()));
        console.log("Owner:", EnsRegistry(proxyAddr).owner());

        return address(newImplContract);
    }
}
