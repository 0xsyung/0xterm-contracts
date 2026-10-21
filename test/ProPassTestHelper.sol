// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProPass} from "../src/ProPass.sol";

/**
 * @dev Shared ProPass deploy + buy helpers for Soft ACK #139 onlyPro tests.
 *      Implements IERC721Receiver so address(this) can buyPro (ProPass uses _safeMint).
 */
abstract contract ProPassTestHelper is Test, IERC721Receiver {
    ProPass internal proPass;
    uint256 internal constant PRO_PRICE = 0.01 ether;
    uint64 internal constant PRO_PERIOD = 30 days;

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function deployProPass() internal returns (ProPass) {
        ProPass impl = new ProPass();
        proPass = ProPass(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(ProPass.initialize, (PRO_PRICE, PRO_PERIOD))))
        );
        return proPass;
    }

    function buyPro(address who, uint256 periods) internal {
        uint256 cost = PRO_PRICE * periods;
        vm.deal(who, who.balance + cost);
        vm.prank(who);
        proPass.purchase{value: cost}(periods);
    }
}
