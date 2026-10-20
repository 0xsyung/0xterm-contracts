// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProPass} from "../src/ProPass.sol";

/**
 * @title DeployProPass
 * @dev Deploys upgradeable ProPass: UUPS implementation + ERC1967Proxy.
 *      Soft ACK #139 slice 1. Sepolia defaults: pricePerPeriod = 0.01 ether,
 *      periodSeconds = 30 days.
 *
 *      Signer: Foundry keystore via `--account <name>` (or PRIVATE_KEY via forge CLI).
 *      Do not call vm.envUint("PRIVATE_KEY") here — that blocks `--account`.
 *
 * Usage (see script/ProPassDeploy.md):
 *   forge script script/DeployProPass.s.sol:DeployProPass \
 *     --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast
 */
contract DeployProPass is Script {
    uint256 constant SEPOLIA_PRICE_PER_PERIOD = 0.01 ether;
    uint64 constant PERIOD_SECONDS = 30 days;

    function run() external {
        vm.startBroadcast();

        ProPass impl = new ProPass();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeCall(ProPass.initialize, (SEPOLIA_PRICE_PER_PERIOD, PERIOD_SECONDS))
        );

        vm.stopBroadcast();

        ProPass pro = ProPass(address(proxy));
        console2.log("ProPass proxy deployed at:", address(proxy));
        console2.log("ProPass implementation at:", address(impl));
        console2.log("Owner:", pro.owner());
        console2.log("pricePerPeriod (wei):", pro.pricePerPeriod());
        console2.log("periodSeconds:", uint256(pro.periodSeconds()));
        console2.log("Upgradeable: YES (UUPS - use UpgradeProPass.s.sol to upgrade)");
    }
}
