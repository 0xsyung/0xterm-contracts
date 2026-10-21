// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Billboard} from "../src/Billboard.sol";
import {Chat} from "../src/Chat.sol";
import {EnsRegistry} from "../src/EnsRegistry.sol";
import {PortfolioShare} from "../src/PortfolioShare.sol";
import {WillFactory} from "../src/WillFactory.sol";
import {WillVault} from "../src/WillVault.sol";
import {ProPassTestHelper} from "./ProPassTestHelper.sol";

/**
 * @dev Soft ACK #139 slice 2 — onlyPro matrix: non-Pro reverts, Pro succeeds,
 *      Will remains ungated.
 */
contract OnlyProTest is ProPassTestHelper {
    Billboard board;
    Chat chat;
    EnsRegistry ens;
    PortfolioShare share;
    WillFactory willFactory;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant FEE = 0.0001 ether;

    function setUp() public {
        deployProPass();
        board = Billboard(
            address(
                new ERC1967Proxy(address(new Billboard(address(proPass))), abi.encodeCall(Billboard.initialize, (FEE)))
            )
        );
        chat = Chat(
            address(
                new ERC1967Proxy(address(new Chat(address(proPass))), abi.encodeCall(Chat.initialize, (FEE, "lobby")))
            )
        );
        ens = EnsRegistry(
            address(
                new ERC1967Proxy(address(new EnsRegistry(address(proPass))), abi.encodeCall(EnsRegistry.initialize, ()))
            )
        );
        share = PortfolioShare(
            address(
                new ERC1967Proxy(
                    address(new PortfolioShare(address(proPass))), abi.encodeCall(PortfolioShare.initialize, (FEE))
                )
            )
        );
        WillVault willImpl = new WillVault();
        willFactory = new WillFactory(address(willImpl));
    }

    function test_NonPro_MutativesRevert_ProSucceeds() public {
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        vm.prank(alice);
        vm.expectRevert("Billboard: not Pro");
        board.post{value: FEE}("x");

        buyPro(alice, 1);
        vm.prank(alice);
        board.post{value: FEE}("gm");
        assertEq(board.postCount(), 1);

        vm.prank(bob);
        vm.expectRevert("PortfolioShare: not Pro");
        share.share{value: FEE}(hex"01");

        buyPro(bob, 1);
        vm.prank(bob);
        share.share{value: FEE}(hex"01");
        (, bool active,) = share.get(bob);
        assertTrue(active);
    }

    function test_Will_Create_Ungated_WithoutPro() public {
        // Soft ACK lock B / #247 lock 10 — Will has no ProPass gate in v1.
        address stranger = makeAddr("willUser");
        address heir = makeAddr("heir");
        assertFalse(proPass.isPro(stranger));
        vm.prank(stranger);
        address vault = willFactory.create(heir, 90 days);
        assertTrue(vault != address(0));
        assertEq(willFactory.vaultOf(stranger), vault);
        assertEq(WillVault(payable(vault)).owner(), stranger);
    }

    function test_Reads_Free() public view {
        assertEq(board.postCount(), 0);
        assertEq(chat.messageCount(), 0);
        assertEq(ens.addr(bytes32(0)), address(0));
        assertEq(share.ownerCount(), 0);
        assertFalse(proPass.isPro(alice));
    }
}
