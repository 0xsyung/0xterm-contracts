// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ProPass} from "../src/ProPass.sol";

/**
 * @title UpgradeProPass
 * @dev UUPS upgrade: deploy a new ProPass implementation and point the existing
 *      proxy at it via upgradeToAndCall(newImpl, ""). The proxy owns storage
 *      (token ownership, expiresAt, price, etc.), so membership is preserved.
 *
 *      Only the proxy owner may run this. Bare startBroadcast for `--account`.
 *
 * Usage:
 *   forge script script/UpgradeProPass.s.sol:UpgradeProPass \
 *     --rpc-url $RPC_URL --account deployer \
 *     --sig "run(address)" <PROXY_ADDRESS> --broadcast
 */
contract UpgradeProPass is Script {
    function run(address proxyAddr) external returns (address newImpl) {
        vm.startBroadcast();

        ProPass newImplContract = new ProPass();
        ProPass(proxyAddr).upgradeToAndCall(address(newImplContract), "");

        vm.stopBroadcast();

        console2.log("ProPass upgraded. Proxy:", proxyAddr);
        console2.log("New implementation at:", address(newImplContract));
        console2.log("Owner:", ProPass(proxyAddr).owner());

        return address(newImplContract);
    }
}
