// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PortfolioShare.sol";

/**
 * @title UpgradePortfolioShare
 * @dev Soft ACK #139 slice 2: PortfolioShare(proPass) upgrade.
 *      --sig "run(address,address)" <PROXY> <PRO_PASS>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract UpgradePortfolioShare is Script {
    function run(address proxyAddr, address proPass) external returns (address newImpl) {
        require(proPass != address(0), "UpgradePortfolioShare: zero proPass");
        vm.startBroadcast();

        PortfolioShare newImplContract = new PortfolioShare(proPass);
        PortfolioShare(proxyAddr).upgradeToAndCall(address(newImplContract), "");

        vm.stopBroadcast();

        console.log("PortfolioShare upgraded. Proxy:", proxyAddr);
        console.log("New implementation at:", address(newImplContract));
        console.log("ProPass:", address(PortfolioShare(proxyAddr).proPass()));
        console.log("Owner:", PortfolioShare(proxyAddr).owner());

        return address(newImplContract);
    }
}
