// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WillVault} from "../src/WillVault.sol";
import {WillFactory} from "../src/WillFactory.sol";

contract WillFactoryTest is Test {
    WillFactory factory;
    address impl;

    address owner = makeAddr("owner");
    address heir = makeAddr("heir");
    uint64 constant DELAY = 90 days;

    function setUp() public {
        WillVault v = new WillVault();
        impl = address(v);
        factory = new WillFactory(impl);
    }

    function test_Create_StoresVaultOf_EmitsVaultCreated() public {
        vm.prank(owner);
        vm.expectEmit(true, false, true, true);
        emit WillFactory.VaultCreated(owner, address(0), heir, DELAY);
        address vault = factory.create(heir, DELAY);

        assertEq(factory.vaultOf(owner), vault);
        assertTrue(vault != address(0));
        assertEq(factory.implementation(), impl);
        assertEq(WillVault(payable(vault)).owner(), owner);
        assertEq(WillVault(payable(vault)).heir(), heir);
        assertEq(WillVault(payable(vault)).delay(), DELAY);
    }

    function test_Create_SecondRevertsVaultExists() public {
        vm.prank(owner);
        factory.create(heir, DELAY);

        vm.prank(owner);
        vm.expectRevert(WillFactory.VaultExists.selector);
        factory.create(heir, DELAY);
    }

    function test_Create_ZeroHeirReverts() public {
        vm.prank(owner);
        vm.expectRevert(WillFactory.ZeroAddress.selector);
        factory.create(address(0), DELAY);
    }

    function test_Create_HeirIsOwnerReverts() public {
        vm.prank(owner);
        vm.expectRevert(WillFactory.HeirIsOwner.selector);
        factory.create(owner, DELAY);
    }

    function test_Create_DifferentOwnersDistinctVaults() public {
        address owner2 = makeAddr("owner2");
        vm.prank(owner);
        address v1 = factory.create(heir, DELAY);
        vm.prank(owner2);
        address v2 = factory.create(heir, DELAY);
        assertTrue(v1 != v2);
        assertEq(factory.vaultOf(owner), v1);
        assertEq(factory.vaultOf(owner2), v2);
    }

    function test_Constructor_ZeroImplReverts() public {
        vm.expectRevert(WillFactory.ZeroAddress.selector);
        new WillFactory(address(0));
    }
}
