// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GroupChat} from "../src/GroupChat.sol";
import {GroupChatFactory} from "../src/GroupChatFactory.sol";
import {ProPassTestHelper} from "./ProPassTestHelper.sol";

contract GroupChatTest is ProPassTestHelper {
    GroupChat group;
    GroupChatFactory factory;
    uint256 constant FEE = 0.0001 ether;
    bytes12 constant IV = bytes12(hex"0102030405060708090a0b0c");
    bytes constant CT = hex"aabbccddeeff00112233445566778899";
    bytes constant SENDER_KEY = hex"020000000000000000000000000000000000000000000000000000000000000000";

    uint256 aliceKey = 0xA11CE;
    address alice;
    uint256 bobKey = 0xB0B0;
    address bob;
    uint256 carolKey = 0xC0C0;
    address carol;

    function setUp() public {
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);
        carol = vm.addr(carolKey);

        deployProPass();
        buyPro(alice, 1);
        buyPro(bob, 1);
        buyPro(carol, 1);

        GroupChat impl = new GroupChat(address(proPass));
        factory = new GroupChatFactory(address(impl), address(proPass));

        vm.prank(alice);
        address g = factory.deploy("crew", FEE);
        group = GroupChat(g);
    }

    function test_Create_OwnerIsSoleMember() public view {
        assertEq(group.owner(), alice);
        assertTrue(group.isMember(alice));
        assertEq(group.memberCount(), 1);
        assertTrue(group.alive());
        assertEq(group.name(), "crew");
        assertEq(group.fee(), FEE);
        assertEq(address(group.proPass()), address(proPass));
    }

    function test_Factory_Deploy_NotPro_Reverts() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert("GroupChatFactory: not Pro");
        factory.deploy("nope", FEE);
    }

    function test_InviteJoinLeave_TransferToOldest() public {
        vm.prank(alice);
        group.invite(bob);
        vm.prank(bob);
        group.join();
        assertTrue(group.isMember(bob));
        assertEq(group.memberCount(), 2);

        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        group.invite(carol);
        vm.prank(carol);
        group.join();

        vm.prank(alice);
        group.leave();
        assertFalse(group.isMember(alice));
        assertEq(group.owner(), bob);
        assertTrue(group.alive());
        assertEq(group.memberCount(), 2);
    }

    function test_LastMemberLeave_Dies() public {
        vm.prank(alice);
        group.leave();
        assertFalse(group.alive());
        assertEq(group.memberCount(), 0);

        vm.prank(bob);
        vm.expectRevert("GroupChat: dead");
        group.join();
    }

    function test_SendMessage_MembersOnly() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        group.sendMessage{value: FEE}(IV, SENDER_KEY, CT);
        assertEq(group.messageCount(), 1);

        vm.prank(bob);
        vm.expectRevert("GroupChat: not a member");
        group.sendMessage(IV, SENDER_KEY, CT);
    }

    function test_SendMessage_NotPro_Reverts() public {
        address stranger = makeAddr("stranger");
        // even if somehow a member — gate fires first for non-Pro
        vm.deal(stranger, FEE);
        vm.prank(stranger);
        vm.expectRevert("GroupChat: not Pro");
        group.sendMessage{value: FEE}(IV, SENDER_KEY, CT);
    }

    function test_Invite_OwnerOnly() public {
        vm.prank(bob);
        vm.expectRevert();
        group.invite(carol);
    }

    function test_Join_RequiresInvite() public {
        vm.prank(bob);
        vm.expectRevert("GroupChat: not invited");
        group.join();
    }

    function test_TransferOwnership_MustBeMember() public {
        vm.prank(alice);
        vm.expectRevert("GroupChat: not a member");
        group.transferOwnership(bob);

        vm.prank(alice);
        group.invite(bob);
        vm.prank(bob);
        group.join();

        vm.prank(alice);
        group.transferOwnership(bob);
        assertEq(group.owner(), bob);
    }

    function test_Dead_BlocksSend() public {
        vm.prank(alice);
        group.leave();
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert("GroupChat: dead");
        group.sendMessage{value: FEE}(IV, SENDER_KEY, CT);
    }

    function test_SetEnvelope() public {
        bytes memory wrapped = hex"deadbeef";
        vm.prank(alice);
        group.invite(bob);
        vm.prank(alice);
        group.setEnvelope(bob, wrapped);
        assertEq(group.getEnvelope(bob), wrapped);
    }
}
