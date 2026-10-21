// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/Billboard.sol";

/**
 * @title DeployBillboard
 * @dev Soft ACK #139 slice 2: Billboard impl takes ProPass proxy.
 *      Usage: forge script ... --sig "run(address)" <PRO_PASS_PROXY>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract DeployBillboard is Script {
    uint256 constant INITIAL_FEE = 100000000000000;

    function run(address proPass) external {
        require(proPass != address(0), "DeployBillboard: zero proPass");
        vm.startBroadcast();

        Billboard impl = new Billboard(proPass);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(Billboard.initialize, (INITIAL_FEE)));

        vm.stopBroadcast();

        console.log("Billboard proxy deployed at:", address(proxy));
        console.log("Billboard implementation at:", address(impl));
        console.log("ProPass:", address(Billboard(address(proxy)).proPass()));
        console.log("Initial fee (wei):", Billboard(address(proxy)).fee());
        console.log("Owner:", Billboard(address(proxy)).owner());
    }
}
