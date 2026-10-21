// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupChatFactory} from "../src/GroupChatFactory.sol";

/**
 * @title DeployGroupChat
 * @dev Soft ACK #139 slice 2: GroupChat + factory take ProPass proxy.
 *      Usage: forge script ... --sig "run(address)" <PRO_PASS_PROXY>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY env).
 */
contract DeployGroupChat is Script {
    function run(address proPass) external {
        require(proPass != address(0), "DeployGroupChat: zero proPass");
        vm.startBroadcast();
        GroupChat impl = new GroupChat(proPass);
        GroupChatFactory factory = new GroupChatFactory(address(impl), proPass);
        vm.stopBroadcast();
        console2.log("GroupChat implementation:", address(impl));
        console2.log("GroupChatFactory:", address(factory));
        console2.log("ProPass:", proPass);
    }
}
