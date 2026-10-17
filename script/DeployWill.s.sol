// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {WillVault} from "../src/WillVault.sol";
import {WillFactory} from "../src/WillFactory.sol";

/// Deploy shared WillVault implementation + factory. Fill WILL_FACTORY in the app.
/// Testnets only — no mainnet keys.
contract DeployWill is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        WillVault impl = new WillVault();
        WillFactory factory = new WillFactory(address(impl));
        vm.stopBroadcast();
        console2.log("WillVault implementation:", address(impl));
        console2.log("WillFactory:", address(factory));
    }
}
