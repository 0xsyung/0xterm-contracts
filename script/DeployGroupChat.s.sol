// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupChatFactory} from "../src/GroupChatFactory.sol";

/// Deploy shared GroupChat implementation + factory. Fill GROUP_CHAT_* in the app.
contract DeployGroupChat is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        GroupChat impl = new GroupChat();
        GroupChatFactory factory = new GroupChatFactory(address(impl));
        vm.stopBroadcast();
        console2.log("GroupChat implementation:", address(impl));
        console2.log("GroupChatFactory:", address(factory));
    }
}
