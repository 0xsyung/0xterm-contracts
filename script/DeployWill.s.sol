// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {WillVault} from "../src/WillVault.sol";
import {WillFactory} from "../src/WillFactory.sol";

/// Deploy shared WillVault implementation + factory. Fill WILL_FACTORY in the app.
/// Testnets only — no mainnet keys.
/// Signer: Foundry keystore via `--account <name>` (or PRIVATE_KEY via forge CLI).
/// Do not call vm.envUint("PRIVATE_KEY") here — that blocks `--account`.
contract DeployWill is Script {
    function run() external {
        vm.startBroadcast();
        WillVault impl = new WillVault();
        WillFactory factory = new WillFactory(address(impl));
        vm.stopBroadcast();
        console2.log("WillVault implementation:", address(impl));
        console2.log("WillFactory:", address(factory));
    }
}
