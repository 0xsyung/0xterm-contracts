// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Chat.sol";

/**
 * @title UpgradeChat
 * @dev Soft ACK #139 slice 2: deploy Chat(proPass) impl and point proxy at it.
 *
 * Usage:
 *   forge script script/UpgradeChat.s.sol:UpgradeChat \
 *     --rpc-url $RPC_URL --account deployer --sender <OWNER> \
 *     --sig "run(address,address)" <PROXY> <PRO_PASS> --broadcast --slow
 *
 * Sepolia ProPass: 0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e
 */
contract UpgradeChat is Script {
    function run(address proxyAddr, address proPass) external returns (address newImpl) {
        require(proPass != address(0), "UpgradeChat: zero proPass");
        vm.startBroadcast();

        Chat newImplContract = new Chat(proPass);
        Chat(proxyAddr).upgradeToAndCall(address(newImplContract), "");

        vm.stopBroadcast();

        console.log("Chat upgraded. Proxy:", proxyAddr);
        console.log("New implementation at:", address(newImplContract));
        console.log("ProPass:", address(Chat(proxyAddr).proPass()));
        console.log("Owner:", Chat(proxyAddr).owner());

        return address(newImplContract);
    }
}
