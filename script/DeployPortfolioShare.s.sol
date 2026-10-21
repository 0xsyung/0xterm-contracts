// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/PortfolioShare.sol";

/**
 * @title DeployPortfolioShare
 * @dev Soft ACK #139 slice 2: PortfolioShare impl takes ProPass proxy.
 *      Usage: forge script ... --sig "run(address)" <PRO_PASS_PROXY>
 *      Bare vm.startBroadcast for --account (no PRIVATE_KEY).
 */
contract DeployPortfolioShare is Script {
    uint256 constant INITIAL_FEE = 100000000000000;

    function run(address proPass) external {
        require(proPass != address(0), "DeployPortfolioShare: zero proPass");
        vm.startBroadcast();

        PortfolioShare impl = new PortfolioShare(proPass);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(PortfolioShare.initialize, (INITIAL_FEE)));

        vm.stopBroadcast();

        console.log("PortfolioShare proxy deployed at:", address(proxy));
        console.log("PortfolioShare implementation at:", address(impl));
        console.log("ProPass:", address(PortfolioShare(address(proxy)).proPass()));
        console.log("Initial fee (wei):", PortfolioShare(address(proxy)).fee());
        console.log("Owner:", PortfolioShare(address(proxy)).owner());
    }
}
