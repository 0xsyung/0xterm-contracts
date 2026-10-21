// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Chat.sol";
import "../src/ChatFactory.sol";

/**
 * @title DeployChatFactory
 * @dev Soft ACK #139 slice 2: Chat + factory both take ProPass proxy.
 *      Usage: forge script ... --sig "run(address)" <PRO_PASS_PROXY>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract DeployChatFactory is Script {
    uint256 constant INITIAL_FEE = 100000000000000;

    function run(address proPass) external {
        require(proPass != address(0), "DeployChatFactory: zero proPass");
        vm.startBroadcast();

        Chat impl = new Chat(proPass);
        ChatFactory factory = new ChatFactory(address(impl), proPass);

        vm.stopBroadcast();

        console.log("Chat implementation at:", address(impl));
        console.log("ChatFactory at:", address(factory));
        console.log("ProPass:", proPass);
        console.log("Default fee hint (wei):", INITIAL_FEE);
        console.log("Factory owner:", factory.owner());
    }
}
