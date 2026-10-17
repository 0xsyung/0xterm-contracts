// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title WillVault
 * @dev Immutable (non-upgradeable) dead-man / inactivity vault. Owner deposits
 *      ETH + ERC-20s, heartbeats to push claimableAt out; after `delay` seconds
 *      of inactivity the sole heir may claim. Owner can cancel anytime while
 *      able to sign. Deployed as EIP-1167 clones via WillFactory.
 *
 *      Companion to 0xterm-app Soft ACK #26. Testnets only until audit gate.
 */
contract WillVault is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint64 public constant MIN_DELAY = 7 days; // 604800
    uint64 public constant MAX_DELAY = 730 days; // 63072000
    uint256 public constant MAX_TOKENS = 20;

    address private _owner;
    address private _heir;
    uint64 private _delay;
    uint64 private _lastHeartbeat;
    bool private _claimed;
    bool private _cancelled;
    address[] private _tokens;
    mapping(address => bool) private _tracked;

    error NotOwner();
    error NotHeir();
    error ZeroAddress();
    error HeirIsOwner();
    error DelayTooShort();
    error DelayTooLong();
    error TooEarly(uint64 claimableAt);
    error AlreadyClaimed();
    error CancelledVault();
    error TokenListFull();
    error ZeroAmount();

    event Heartbeat(address indexed owner, uint64 timestamp);
    event HeirChanged(address indexed owner, address indexed oldHeir, address indexed newHeir);
    event DelayChanged(address indexed owner, uint64 oldDelay, uint64 newDelay);
    event Deposited(address indexed from, address indexed token, uint256 amount);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    event Cancelled(address indexed owner);
    event Claimed(address indexed heir, uint64 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    modifier onlyHeir() {
        if (msg.sender != _heir) revert NotHeir();
        _;
    }

    modifier whenActive() {
        if (_claimed) revert AlreadyClaimed();
        if (_cancelled) revert CancelledVault();
        _;
    }

    function initialize(address owner_, address heir_, uint64 delaySeconds) external initializer {
        if (owner_ == address(0) || heir_ == address(0)) revert ZeroAddress();
        if (heir_ == owner_) revert HeirIsOwner();
        _checkDelay(delaySeconds);

        _owner = owner_;
        _heir = heir_;
        _delay = delaySeconds;
        _lastHeartbeat = uint64(block.timestamp);
    }

    // ─── views ───────────────────────────────────────────────────────────────

    function owner() external view returns (address) {
        return _owner;
    }

    function heir() external view returns (address) {
        return _heir;
    }

    function delay() external view returns (uint64) {
        return _delay;
    }

    function lastHeartbeat() external view returns (uint64) {
        return _lastHeartbeat;
    }

    function claimed() external view returns (bool) {
        return _claimed;
    }

    function cancelled() external view returns (bool) {
        return _cancelled;
    }

    function claimableAt() public view returns (uint64) {
        return _lastHeartbeat + _delay;
    }

    function isClaimable() external view returns (bool) {
        return !_claimed && !_cancelled && block.timestamp >= claimableAt();
    }

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ─── owner actions ───────────────────────────────────────────────────────

    function heartbeat() external onlyOwner whenActive {
        _bumpHeartbeat();
    }

    function setHeir(address newHeir) external onlyOwner whenActive {
        if (newHeir == address(0)) revert ZeroAddress();
        if (newHeir == _owner) revert HeirIsOwner();
        address old = _heir;
        _heir = newHeir;
        _bumpHeartbeat();
        emit HeirChanged(_owner, old, newHeir);
    }

    function setDelay(uint64 newDelay) external onlyOwner whenActive {
        _checkDelay(newDelay);
        uint64 old = _delay;
        _delay = newDelay;
        _bumpHeartbeat();
        emit DelayChanged(_owner, old, newDelay);
    }

    function withdraw(address token, uint256 amt) external onlyOwner whenActive nonReentrant {
        if (amt == 0) revert ZeroAmount();
        _bumpHeartbeat();
        _transferOut(msg.sender, token, amt);
        emit Withdrawn(msg.sender, token, amt);
    }

    function cancel() external onlyOwner whenActive nonReentrant {
        _cancelled = true;
        _bumpHeartbeat();
        _payout(_owner);
        emit Cancelled(_owner);
    }

    // ─── heir ────────────────────────────────────────────────────────────────

    function claim() external onlyHeir whenActive nonReentrant {
        uint64 claimAt = claimableAt();
        if (block.timestamp < claimAt) revert TooEarly(claimAt);
        _claimed = true;
        _payout(_heir);
        emit Claimed(_heir, uint64(block.timestamp));
    }

    // ─── deposits (anyone) ───────────────────────────────────────────────────

    function deposit() external payable whenActive {
        if (msg.value == 0) revert ZeroAmount();
        _track(address(0));
        emit Deposited(msg.sender, address(0), msg.value);
    }

    function depositToken(address token, uint256 amt) external whenActive nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amt == 0) revert ZeroAmount();
        uint256 beforeBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amt);
        uint256 received = IERC20(token).balanceOf(address(this)) - beforeBal;
        if (received == 0) revert ZeroAmount();
        _track(token);
        emit Deposited(msg.sender, token, received);
    }

    // ─── internals ───────────────────────────────────────────────────────────

    function _checkDelay(uint64 d) internal pure {
        if (d < MIN_DELAY) revert DelayTooShort();
        if (d > MAX_DELAY) revert DelayTooLong();
    }

    function _bumpHeartbeat() internal {
        _lastHeartbeat = uint64(block.timestamp);
        emit Heartbeat(_owner, _lastHeartbeat);
    }

    function _track(address token) internal {
        if (_tracked[token]) return;
        if (_tokens.length >= MAX_TOKENS) revert TokenListFull();
        _tracked[token] = true;
        _tokens.push(token);
    }

    function _payout(address to) internal {
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token = _tokens[i];
            if (token == address(0)) continue;
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal > 0) {
                IERC20(token).safeTransfer(to, bal);
            }
        }
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool ok,) = to.call{value: ethBal}("");
            require(ok, "WillVault: ETH transfer failed");
        }
    }

    function _transferOut(address to, address token, uint256 amt) internal {
        if (token == address(0)) {
            (bool ok,) = to.call{value: amt}("");
            require(ok, "WillVault: ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amt);
        }
    }

    receive() external payable {
        // Accidental ETH: only count toward ethBalance / claim-cancel payout.
        // Does not auto-track address(0); use deposit() to record in tokens[].
    }
}
