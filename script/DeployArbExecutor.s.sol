// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { ArbExecutor } from "../src/ArbExecutor.sol";

/**
 * @title DeployArbExecutor
 * @dev Deploys the 3-venue atomic arb executor (plain CREATE, keystore account).
 *      The constructor pins the Uniswap V3 swap router used for V3 legs.
 *
 * Usage (testnet only — mainnet run gated behind audit in the app):
 *   export SEPOLIA_RPC_URL=...
 *   forge script script/DeployArbExecutor.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL --account <account-name> --sender <YOUR_ADDRESS>
 *   # dry-run, then re-run with --broadcast
 *
 * Sepolia V3 router (0xterm-app DEX_REGISTRY[11155111] univ3 router).
 */
contract DeployArbExecutor is Script {
    address constant V3_ROUTER_SEPOLIA = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;
    // Sepolia venues (0xterm-app DEX_REGISTRY[11155111]).
    address constant V3_FACTORY_SEPOLIA = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address constant V2_FACTORY_SEPOLIA = 0x26F278090C6C954c302FEfA7e60d0DD2779C1f85;

    function run() external {
        vm.startBroadcast();

        ArbExecutor arb = new ArbExecutor(V3_ROUTER_SEPOLIA, V2_FACTORY_SEPOLIA, V3_FACTORY_SEPOLIA);

        vm.stopBroadcast();

        console.log("ArbExecutor deployed at:", address(arb));
        console.log("v3Router:", arb.v3Router());
        console.log("v2Factory:", arb.v2Factory());
        console.log("v3Factory:", arb.v3Factory());
    }
}
