// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/EnsRegistry.sol";

/**
 * @title DeployENS
 * @dev Soft ACK #139 slice 2: EnsRegistry impl takes ProPass proxy.
 *      Usage: forge script ... --sig "run(address)" <PRO_PASS_PROXY>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract DeployENS is Script {
    function run(address proPass) external {
        require(proPass != address(0), "DeployENS: zero proPass");
        vm.startBroadcast();

        EnsRegistry impl = new EnsRegistry(proPass);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(EnsRegistry.initialize, ()));

        vm.stopBroadcast();

        console.log("ENS proxy deployed at:", address(proxy));
        console.log("ENS implementation at:", address(impl));
        console.log("ProPass:", address(EnsRegistry(address(proxy)).proPass()));
        console.log("Owner:", EnsRegistry(address(proxy)).owner());
    }
}
