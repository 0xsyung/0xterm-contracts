// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Chat.sol";

/**
 * @title DeployChat
 * @dev Soft ACK #139 slice 2: Chat impl constructor takes ProPass proxy.
 *      Usage: forge script ... --sig "run(address)" <PRO_PASS_PROXY>
 *      Sepolia ProPass: 0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e
 *      Bare vm.startBroadcast for Foundry --account keystore (no PRIVATE_KEY).
 */
contract DeployChat is Script {
    uint256 constant INITIAL_FEE = 100000000000000;

    function run(address proPass) external {
        require(proPass != address(0), "DeployChat: zero proPass");
        vm.startBroadcast();

        Chat impl = new Chat(proPass);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(Chat.initialize, (INITIAL_FEE, "lobby")));

        vm.stopBroadcast();

        console.log("Chat proxy deployed at:", address(proxy));
        console.log("Chat implementation at:", address(impl));
        console.log("ProPass:", address(Chat(address(proxy)).proPass()));
        console.log("Initial fee (wei):", Chat(address(proxy)).fee());
        console.log("Owner:", Chat(address(proxy)).owner());
    }
}
