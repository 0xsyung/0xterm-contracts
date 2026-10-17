// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WillVault} from "../src/WillVault.sol";
import {WillFactory} from "../src/WillFactory.sol";
import {MockToken} from "../src/MockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Malicious ERC-20 that attempts to reenter WillVault.claim on transfer.
contract ReentrantToken {
    WillVault public vault;
    bool public attacking;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    string public name = "Reenter";
    string public symbol = "REENT";
    uint8 public decimals = 18;

    function setVault(address v) external {
        vault = WillVault(payable(v));
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address spender, uint256 amt) external returns (bool) {
        allowance[msg.sender][spender] = amt;
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        if (attacking && address(vault) != address(0)) {
            attacking = false;
            // Attempt reentrant claim; guard / latch must block double-pay without
            // reverting the outer transfer (else payout itself would brick).
            try vault.claim() {} catch {}
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amt, "allowance");
        allowance[from][msg.sender] = a - amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function arm() external {
        attacking = true;
    }
}

contract WillVaultTest is Test {
    WillFactory factory;
    WillVault vault;
    MockToken tokenA;
    MockToken tokenB;

    address owner = makeAddr("owner");
    address heir = makeAddr("heir");
    address stranger = makeAddr("stranger");
    uint64 constant DELAY = 90 days;

    event Heartbeat(address indexed owner, uint64 timestamp);
    event Claimed(address indexed heir, uint64 timestamp);
    event Cancelled(address indexed owner);

    function setUp() public {
        WillVault impl = new WillVault();
        factory = new WillFactory(address(impl));

        vm.prank(owner);
        address v = factory.create(heir, DELAY);
        vault = WillVault(payable(v));

        tokenA = new MockToken("TokenA", "TKA", 18, 1_000_000);
        tokenB = new MockToken("TokenB", "TKB", 18, 1_000_000);
        tokenA.mint(owner, 1000 ether);
        tokenB.mint(owner, 1000 ether);
        vm.deal(owner, 100 ether);
        vm.deal(heir, 1 ether);
        vm.deal(stranger, 10 ether);
    }

    // ─── heartbeat ───────────────────────────────────────────────────────────

    function test_Heartbeat_OnlyOwner_UpdatesLastHeartbeat() public {
        uint64 before_ = vault.lastHeartbeat();
        vm.warp(block.timestamp + 1 days);

        vm.prank(stranger);
        vm.expectRevert(WillVault.NotOwner.selector);
        vault.heartbeat();

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Heartbeat(owner, uint64(block.timestamp));
        vault.heartbeat();
        assertEq(vault.lastHeartbeat(), uint64(block.timestamp));
        assertTrue(vault.lastHeartbeat() > before_);
    }

    // ─── claim timing ────────────────────────────────────────────────────────

    function test_Claim_TooEarlyAtDelayMinusOne_SucceedsAtDelay() public {
        vm.prank(owner);
        vault.deposit{value: 1 ether}();

        vm.prank(owner);
        tokenA.approve(address(vault), 100 ether);
        vm.prank(owner);
        vault.depositToken(address(tokenA), 100 ether);

        vm.prank(owner);
        tokenB.approve(address(vault), 50 ether);
        vm.prank(owner);
        vault.depositToken(address(tokenB), 50 ether);

        uint64 start = vault.lastHeartbeat();
        uint64 claimAt = start + DELAY;

        // delay - 1 → TooEarly
        vm.warp(claimAt - 1);
        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(WillVault.TooEarly.selector, claimAt));
        vault.claim();

        // exactly at delay → succeeds, pays ETH + 2 ERC-20s, latches
        vm.warp(claimAt);
        uint256 heirEthBefore = heir.balance;
        uint256 heirABefore = tokenA.balanceOf(heir);
        uint256 heirBBefore = tokenB.balanceOf(heir);

        vm.prank(heir);
        vault.claim();

        assertTrue(vault.claimed());
        assertEq(heir.balance, heirEthBefore + 1 ether);
        assertEq(tokenA.balanceOf(heir), heirABefore + 100 ether);
        assertEq(tokenB.balanceOf(heir), heirBBefore + 50 ether);
        assertEq(address(vault).balance, 0);
        assertEq(tokenA.balanceOf(address(vault)), 0);
        assertEq(tokenB.balanceOf(address(vault)), 0);

        // further claim / heartbeat / deposit revert
        vm.prank(heir);
        vm.expectRevert(WillVault.AlreadyClaimed.selector);
        vault.claim();

        vm.prank(owner);
        vm.expectRevert(WillVault.AlreadyClaimed.selector);
        vault.heartbeat();

        vm.prank(owner);
        vm.expectRevert(WillVault.AlreadyClaimed.selector);
        vault.deposit{value: 0.1 ether}();
    }

    function test_HeartbeatAfterDelayMinusOne_PushesClaimableOut() public {
        uint64 start = vault.lastHeartbeat();
        vm.warp(start + DELAY - 1);

        vm.prank(owner);
        vault.heartbeat();

        uint64 newAt = vault.claimableAt();
        assertEq(newAt, uint64(block.timestamp) + DELAY);

        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(WillVault.TooEarly.selector, newAt));
        vault.claim();
    }

    // ─── cancel ──────────────────────────────────────────────────────────────

    function test_Cancel_ThenClaimReverts_BalancesToOwner() public {
        vm.prank(owner);
        vault.deposit{value: 2 ether}();
        vm.prank(owner);
        tokenA.approve(address(vault), 10 ether);
        vm.prank(owner);
        vault.depositToken(address(tokenA), 10 ether);

        uint256 ownerEthBefore = owner.balance;
        uint256 ownerABefore = tokenA.balanceOf(owner);

        vm.prank(owner);
        vault.cancel();

        assertTrue(vault.cancelled());
        assertEq(owner.balance, ownerEthBefore + 2 ether);
        assertEq(tokenA.balanceOf(owner), ownerABefore + 10 ether);

        vm.warp(block.timestamp + DELAY + 1);
        vm.prank(heir);
        vm.expectRevert(WillVault.CancelledVault.selector);
        vault.claim();
    }

    // ─── setHeir / setDelay ──────────────────────────────────────────────────

    function test_SetHeir_SetDelay_BoundsAndHeartbeat() public {
        address newHeir = makeAddr("newHeir");
        uint64 t0 = vault.lastHeartbeat();
        vm.warp(block.timestamp + 1 hours);

        vm.prank(owner);
        vault.setHeir(newHeir);
        assertEq(vault.heir(), newHeir);
        assertEq(vault.lastHeartbeat(), uint64(block.timestamp));
        assertTrue(vault.lastHeartbeat() > t0);

        vm.prank(owner);
        vm.expectRevert(WillVault.ZeroAddress.selector);
        vault.setHeir(address(0));

        vm.prank(owner);
        vm.expectRevert(WillVault.HeirIsOwner.selector);
        vault.setHeir(owner);

        vm.prank(owner);
        vm.expectRevert(WillVault.DelayTooShort.selector);
        vault.setDelay(7 days - 1);

        vm.prank(owner);
        vm.expectRevert(WillVault.DelayTooLong.selector);
        vault.setDelay(730 days + 1);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(owner);
        vault.setDelay(30 days);
        assertEq(vault.delay(), 30 days);
        assertEq(vault.lastHeartbeat(), uint64(block.timestamp));
    }

    function test_Initialize_DelayBoundsAndHeirChecks() public {
        WillVault impl = new WillVault();
        WillFactory f2 = new WillFactory(address(impl));
        // owner already has vault on `factory`; use fresh owner
        address o2 = makeAddr("o2");

        vm.prank(o2);
        vm.expectRevert(WillVault.DelayTooShort.selector);
        f2.create(heir, 7 days - 1);

        vm.prank(o2);
        vm.expectRevert(WillVault.DelayTooLong.selector);
        f2.create(heir, 730 days + 1);

        vm.prank(o2);
        vm.expectRevert(WillFactory.HeirIsOwner.selector);
        f2.create(o2, DELAY);

        vm.prank(o2);
        vm.expectRevert(WillFactory.ZeroAddress.selector);
        f2.create(address(0), DELAY);
    }

    // ─── TokenListFull ───────────────────────────────────────────────────────

    function test_TokenListFull_At21stDistinct() public {
        // deposit ETH → address(0) is token #1
        vm.prank(owner);
        vault.deposit{value: 0.01 ether}();

        // 19 more ERC-20s → total 20
        for (uint256 i = 0; i < 19; i++) {
            MockToken t = new MockToken("T", "T", 18, 1000);
            t.mint(owner, 1 ether);
            vm.prank(owner);
            t.approve(address(vault), 1 ether);
            vm.prank(owner);
            vault.depositToken(address(t), 1 ether);
        }
        assertEq(vault.tokens().length, 20);

        MockToken extra = new MockToken("X", "X", 18, 1000);
        extra.mint(owner, 1 ether);
        vm.prank(owner);
        extra.approve(address(vault), 1 ether);
        vm.prank(owner);
        vm.expectRevert(WillVault.TokenListFull.selector);
        vault.depositToken(address(extra), 1 ether);
    }

    // ─── reentrancy ──────────────────────────────────────────────────────────

    function test_ReentrancyAttacker_CannotDoubleClaim() public {
        ReentrantToken rt = new ReentrantToken();
        rt.mint(owner, 100 ether);
        rt.setVault(address(vault));

        vm.prank(owner);
        rt.approve(address(vault), 100 ether);
        vm.prank(owner);
        vault.depositToken(address(rt), 100 ether);

        vm.prank(owner);
        vault.deposit{value: 1 ether}();

        vm.warp(vault.lastHeartbeat() + DELAY);
        rt.arm();

        uint256 heirEthBefore = heir.balance;
        vm.prank(heir);
        // claim succeeds once; reentrant claim from token.transfer is blocked
        vault.claim();

        assertTrue(vault.claimed());
        // ETH paid once; reentrant path did not double-pay
        assertEq(heir.balance, heirEthBefore + 1 ether);
        assertEq(address(vault).balance, 0);
    }

    // ─── fuzz ────────────────────────────────────────────────────────────────

    function testFuzz_ClaimNeverSucceedsBeforeDelay(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, DELAY - 1));
        vm.prank(owner);
        vault.deposit{value: 0.1 ether}();

        uint64 start = vault.lastHeartbeat();
        vm.warp(start + elapsed);

        vm.prank(heir);
        vm.expectRevert(abi.encodeWithSelector(WillVault.TooEarly.selector, start + DELAY));
        vault.claim();
    }

    // ─── withdraw / deposit extras ───────────────────────────────────────────

    function test_Withdraw_OnlyOwner_Heartbeats() public {
        vm.prank(owner);
        vault.deposit{value: 5 ether}();
        vm.warp(block.timestamp + 1 days);

        vm.prank(stranger);
        vm.expectRevert(WillVault.NotOwner.selector);
        vault.withdraw(address(0), 1 ether);

        uint256 beforeBal = owner.balance;
        vm.prank(owner);
        vault.withdraw(address(0), 1 ether);
        assertEq(owner.balance, beforeBal + 1 ether);
        assertEq(vault.lastHeartbeat(), uint64(block.timestamp));
    }

    function test_Deposit_ZeroAmountReverts() public {
        vm.prank(owner);
        vm.expectRevert(WillVault.ZeroAmount.selector);
        vault.deposit{value: 0}();
    }

    function test_Claim_NotHeirReverts() public {
        vm.warp(vault.lastHeartbeat() + DELAY);
        vm.prank(stranger);
        vm.expectRevert(WillVault.NotHeir.selector);
        vault.claim();
    }

    function test_IsClaimable_View() public {
        assertFalse(vault.isClaimable());
        vm.warp(vault.lastHeartbeat() + DELAY);
        assertTrue(vault.isClaimable());
    }

    function test_AnyoneMayTopUp() public {
        vm.prank(stranger);
        vault.deposit{value: 0.5 ether}();
        assertEq(vault.ethBalance(), 0.5 ether);
        assertEq(vault.tokens()[0], address(0));
    }
}
