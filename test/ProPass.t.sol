// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ProPass} from "../src/ProPass.sol";
import {ProPassV2} from "./ProPassV2.t.sol";

contract ProPassTest is Test {
    ProPass pro;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address treasury = makeAddr("treasury");

    uint256 constant PRICE = 0.01 ether;
    uint64 constant PERIOD = 30 days;

    receive() external payable {}

    function setUp() public {
        ProPass impl = new ProPass();
        pro = ProPass(address(new ERC1967Proxy(address(impl), abi.encodeCall(ProPass.initialize, (PRICE, PERIOD)))));
    }

    function buyAs(address who, uint256 periods) internal returns (uint256 tokenId) {
        uint256 cost = PRICE * periods;
        vm.deal(who, cost);
        vm.prank(who);
        tokenId = pro.purchase{value: cost}(periods);
    }

    // --- init / metadata -------------------------------------------------------

    function test_Proxy_OwnerPricePeriod_Metadata() public view {
        assertEq(pro.owner(), address(this));
        assertEq(pro.pricePerPeriod(), PRICE);
        assertEq(pro.periodSeconds(), PERIOD);
        assertEq(pro.name(), "0xterm Pro");
        assertEq(pro.symbol(), "PRO");
        assertEq(pro.MAX_PERIODS(), 24);
    }

    function test_Implementation_CannotInitialize() public {
        ProPass impl = new ProPass();
        vm.expectRevert();
        impl.initialize(PRICE, PERIOD);
    }

    function test_Initialize_CannotCallTwice() public {
        vm.expectRevert();
        pro.initialize(PRICE, PERIOD);
    }

    // --- purchase / expiresAt immutable ----------------------------------------

    function test_Purchase_MintsNewToken_ExpiresAtImmutable() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 id = buyAs(alice, 1);
        uint64 expectedExp = uint64(t0 + PERIOD);

        assertEq(id, 1);
        assertEq(pro.ownerOf(id), alice);
        assertEq(pro.balanceOf(alice), 1);
        assertEq(pro.expiresAt(id), expectedExp);
        assertTrue(pro.isPro(alice));

        // warp forward; expiresAt must not change
        vm.warp(t0 + 7 days);
        assertEq(pro.expiresAt(id), expectedExp);
        assertTrue(pro.isPro(alice));
    }

    function test_Purchase_EmitsPurchasedAndTransfer() public {
        uint256 cost = PRICE * 2;
        vm.deal(alice, cost);

        vm.expectEmit(true, true, false, true);
        emit IERC721.Transfer(address(0), alice, 1);

        // Purchased(buyer, tokenId, periods, paid, expiresAt)
        uint64 expectedExp = uint64(block.timestamp + 2 * PERIOD);
        vm.expectEmit(true, true, false, true);
        emit ProPass.Purchased(alice, 1, 2, cost, expectedExp);

        vm.prank(alice);
        pro.purchase{value: cost}(2);
    }

    function test_SecondPurchase_WhilePro_MintsSecondNFT() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 id1 = buyAs(alice, 1);
        uint256 id2 = buyAs(alice, 3);
        uint64 exp1 = uint64(t0 + PERIOD);
        uint64 exp2 = uint64(t0 + 3 * PERIOD);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(pro.balanceOf(alice), 2);
        assertTrue(pro.isPro(alice));
        assertEq(pro.expiresAt(id1), exp1);
        assertEq(pro.expiresAt(id2), exp2);

        // after first expires, still Pro via second
        vm.warp(uint256(exp1) + 1);
        assertFalse(pro.expiresAt(id1) > vm.getBlockTimestamp());
        assertTrue(pro.isPro(alice));
    }

    // --- expiry / transfer / no auto-burn --------------------------------------

    function test_Expired_StillOwned_IsProFalse_Transferable() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 id = buyAs(alice, 1);
        uint64 exp = uint64(t0 + PERIOD);
        assertTrue(pro.isPro(alice));

        vm.warp(uint256(exp) + 1);
        assertEq(pro.ownerOf(id), alice);
        assertEq(pro.balanceOf(alice), 1);
        assertFalse(pro.isPro(alice));
        // expiresAt unchanged
        assertEq(pro.expiresAt(id), exp);

        // transfer expired NFT to bob
        vm.prank(alice);
        pro.transferFrom(alice, bob, id);
        assertEq(pro.ownerOf(id), bob);
        assertFalse(pro.isPro(bob));
        assertFalse(pro.isPro(alice));
    }

    function test_Transfer_ActivePass_MovesProStatus() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 id = buyAs(alice, 1);
        uint64 exp = uint64(t0 + PERIOD);
        assertTrue(pro.isPro(alice));
        assertFalse(pro.isPro(bob));

        vm.prank(alice);
        pro.transferFrom(alice, bob, id);

        assertFalse(pro.isPro(alice));
        assertTrue(pro.isPro(bob));
        assertEq(pro.expiresAt(id), exp);
    }

    // --- revert cases ----------------------------------------------------------

    function test_Purchase_PeriodsZero_Reverts() public {
        vm.deal(alice, PRICE);
        vm.prank(alice);
        vm.expectRevert("ProPass: bad periods");
        pro.purchase{value: PRICE}(0);
    }

    function test_Purchase_PeriodsOverMax_Reverts() public {
        uint256 periods = 25;
        uint256 cost = PRICE * periods;
        vm.deal(alice, cost);
        vm.prank(alice);
        vm.expectRevert("ProPass: bad periods");
        pro.purchase{value: cost}(periods);
    }

    function test_Purchase_MaxPeriods_Ok() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 id = buyAs(alice, 24);
        assertEq(id, 1);
        assertEq(pro.expiresAt(id), uint64(t0 + 24 * PERIOD));
        assertTrue(pro.isPro(alice));
    }

    function test_Purchase_WrongETH_Reverts() public {
        vm.deal(alice, PRICE * 2);
        vm.prank(alice);
        vm.expectRevert("ProPass: wrong ETH");
        pro.purchase{value: PRICE - 1}(1);

        vm.prank(alice);
        vm.expectRevert("ProPass: wrong ETH");
        pro.purchase{value: PRICE + 1}(1);
    }

    function test_ExpiresAt_UnknownToken_Reverts() public {
        vm.expectRevert();
        pro.expiresAt(999);
    }

    // --- owner admin -----------------------------------------------------------

    function test_SetPricePerPeriod_OnlyOwner() public {
        pro.setPricePerPeriod(0.02 ether);
        assertEq(pro.pricePerPeriod(), 0.02 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        pro.setPricePerPeriod(0.03 ether);
    }

    function test_SetPrice_AffectsNextPurchase() public {
        buyAs(alice, 1);
        pro.setPricePerPeriod(0.05 ether);

        vm.deal(bob, 0.05 ether);
        vm.prank(bob);
        uint256 id = pro.purchase{value: 0.05 ether}(1);
        assertEq(id, 2);
        assertTrue(pro.isPro(bob));
    }

    function test_Withdraw_OnlyOwner_Partial() public {
        buyAs(alice, 2); // 0.02 ether in contract
        buyAs(bob, 1); // +0.01 = 0.03

        uint256 before = treasury.balance;
        pro.withdraw(payable(treasury), 0.02 ether);
        assertEq(treasury.balance, before + 0.02 ether);
        assertEq(address(pro).balance, 0.01 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        pro.withdraw(payable(alice), 0.01 ether);
    }

    function test_Withdraw_BadAmount_Reverts() public {
        buyAs(alice, 1);
        vm.expectRevert("ProPass: bad amount");
        pro.withdraw(payable(treasury), 0);

        vm.expectRevert("ProPass: bad amount");
        pro.withdraw(payable(treasury), PRICE + 1);

        vm.expectRevert("ProPass: zero to");
        pro.withdraw(payable(address(0)), PRICE);
    }

    // --- UUPS ------------------------------------------------------------------

    function test_Upgrade_OnlyOwner() public {
        ProPassV2 implV2 = new ProPassV2();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        pro.upgradeToAndCall(address(implV2), "");

        pro.upgradeToAndCall(address(implV2), "");
    }

    function test_Upgrade_PreservesMembership() public {
        uint256 id = buyAs(alice, 2);
        uint64 exp = pro.expiresAt(id);

        ProPassV2 implV2 = new ProPassV2();
        pro.upgradeToAndCall(address(implV2), "");

        ProPassV2(address(pro)).setVersionTag(42);
        assertEq(ProPassV2(address(pro)).versionTag(), 42);
        assertEq(pro.ownerOf(id), alice);
        assertEq(pro.expiresAt(id), exp);
        assertTrue(pro.isPro(alice));
        assertEq(pro.pricePerPeriod(), PRICE);
    }

    // --- tokenURI (Soft ACK #139 Lock I) ----------------------------------------

    function test_TokenURI_DataJsonBase64_Fields() public {
        uint256 t0 = vm.getBlockTimestamp();
        uint256 id = buyAs(alice, 2);
        uint64 exp = uint64(t0 + 2 * PERIOD);

        string memory uri = pro.tokenURI(id);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));

        string memory b64 = _stripPrefix(uri, "data:application/json;base64,");
        string memory json = string(Base64.decode(b64));

        assertTrue(_contains(json, '"name":"0xterm Pro #1"'));
        assertTrue(_contains(json, '"image":"https://0xterm.xyz/propass.png"'));
        assertTrue(
            _contains(
                json, '"description":"0xterm Pro membership. Hold any non-expired pass for Pro access on 0xterm."'
            )
        );
        assertTrue(_contains(json, string(abi.encodePacked('"value":', vm.toString(uint256(exp))))));
        assertEq(pro.IMAGE_URI(), "https://0xterm.xyz/propass.png");
    }

    function test_TokenURI_SharedImage_PerTokenName() public {
        buyAs(alice, 1);
        buyAs(bob, 1);

        string memory json1 = string(Base64.decode(_stripPrefix(pro.tokenURI(1), "data:application/json;base64,")));
        string memory json2 = string(Base64.decode(_stripPrefix(pro.tokenURI(2), "data:application/json;base64,")));

        assertTrue(_contains(json1, '"name":"0xterm Pro #1"'));
        assertTrue(_contains(json2, '"name":"0xterm Pro #2"'));
        assertTrue(_contains(json1, '"image":"https://0xterm.xyz/propass.png"'));
        assertTrue(_contains(json2, '"image":"https://0xterm.xyz/propass.png"'));
    }

    function test_TokenURI_UnknownToken_Reverts() public {
        vm.expectRevert();
        pro.tokenURI(999);
    }

    function test_TokenURI_SurvivesUpgrade() public {
        uint256 id = buyAs(alice, 1);
        string memory beforeUri = pro.tokenURI(id);

        ProPassV2 implV2 = new ProPassV2();
        pro.upgradeToAndCall(address(implV2), "");

        // V2 inherits tokenURI; membership + metadata shape preserved
        assertEq(pro.tokenURI(id), beforeUri);
        assertTrue(
            _contains(
                string(Base64.decode(_stripPrefix(pro.tokenURI(id), "data:application/json;base64,"))),
                '"image":"https://0xterm.xyz/propass.png"'
            )
        );
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        if (sb.length < pb.length) return false;
        for (uint256 i = 0; i < pb.length; i++) {
            if (sb[i] != pb[i]) return false;
        }
        return true;
    }

    function _stripPrefix(string memory s, string memory prefix) internal pure returns (string memory) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        require(sb.length >= pb.length, "prefix");
        bytes memory out = new bytes(sb.length - pb.length);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = sb[i + pb.length];
        }
        return string(out);
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || h.length < n.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    // --- enumerable ------------------------------------------------------------

    function test_Enumerable_TokenOfOwnerByIndex() public {
        buyAs(alice, 1);
        buyAs(alice, 1);
        assertEq(pro.tokenOfOwnerByIndex(alice, 0), 1);
        assertEq(pro.tokenOfOwnerByIndex(alice, 1), 2);
        assertEq(pro.totalSupply(), 2);
    }
}
