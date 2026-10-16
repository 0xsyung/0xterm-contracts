// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GroupChat
 * @dev Encrypted group messaging stored on-chain. Opaque ciphertext only —
 *      decryption happens in the browser via a per-group envelope secret that
 *      current members hold. Self-managed membership with owner invite/transfer;
 *      when the last member leaves the group is dead (alive()==false).
 *
 *      Distinct from Chat (1:1) and from named network-wide channels (#58).
 *      Deployed as EIP-1167 clones via GroupChatFactory (testnets only).
 */
contract GroupChat is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public fee;

    struct Message {
        address from;
        uint256 timestamp;
        bytes12 iv;
        bytes senderKey;
        bytes ciphertext;
    }

    struct MemberInfo {
        bool active;
        uint64 joinedAt;
    }

    mapping(address => MemberInfo) private _members;
    address[] private _memberList;
    mapping(address => bool) public invited;
    mapping(address => bytes) public keys;
    /// @dev Owner-wrapped envelope secret for a member (opaque to the contract).
    mapping(address => bytes) public envelopes;

    Message[] private _messages;
    bool private _alive;
    string private _name;

    event MessageSent(address indexed from, bytes32 indexed id, uint256 timestamp, uint256 len);
    event MemberInvited(address indexed who);
    event MemberJoined(address indexed who, uint64 joinedAt);
    event MemberLeft(address indexed who);
    event GroupDied();
    event FeeChanged(uint256 newFee);
    event FeeWithdrawn(address indexed to, uint256 amount);
    event PublicKeyRegistered(address indexed who, bytes key);
    event EnvelopeSet(address indexed who);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 initialFee, string calldata name_, address initialOwner) public initializer {
        uint256 len = bytes(name_).length;
        require(len > 0 && len <= 32, "GroupChat: bad name");
        require(initialOwner != address(0), "GroupChat: zero owner");
        __Ownable_init(initialOwner);
        fee = initialFee;
        _name = name_;
        _alive = true;
        _addMember(initialOwner);
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function alive() external view returns (bool) {
        return _alive;
    }

    function isMember(address who) public view returns (bool) {
        return _members[who].active;
    }

    function getMembers() external view returns (address[] memory) {
        return _memberList;
    }

    function memberCount() external view returns (uint256) {
        return _memberList.length;
    }

    function messageCount() external view returns (uint256) {
        return _messages.length;
    }

    function invite(address who) external onlyOwner {
        require(_alive, "GroupChat: dead");
        require(who != address(0), "GroupChat: zero address");
        require(!_members[who].active, "GroupChat: already member");
        invited[who] = true;
        emit MemberInvited(who);
    }

    function join() external {
        require(_alive, "GroupChat: dead");
        require(invited[msg.sender], "GroupChat: not invited");
        require(!_members[msg.sender].active, "GroupChat: already member");
        invited[msg.sender] = false;
        _addMember(msg.sender);
    }

    function leave() external {
        require(_members[msg.sender].active, "GroupChat: not a member");
        bool wasOwner = msg.sender == owner();
        _removeMember(msg.sender);
        delete envelopes[msg.sender];
        emit MemberLeft(msg.sender);

        if (_memberList.length == 0) {
            _alive = false;
            emit GroupDied();
            return;
        }

        if (wasOwner) {
            address oldest = _memberList[0];
            uint64 oldestAt = _members[oldest].joinedAt;
            for (uint256 i = 1; i < _memberList.length; i++) {
                address m = _memberList[i];
                uint64 joined = _members[m].joinedAt;
                if (joined < oldestAt || (joined == oldestAt && uint160(m) < uint160(oldest))) {
                    oldest = m;
                    oldestAt = joined;
                }
            }
            _transferOwnership(oldest);
        }
    }

    /// @notice Immediate owner transfer. New owner must already be a member.
    function transferOwnership(address newOwner) public override onlyOwner {
        require(_alive, "GroupChat: dead");
        require(newOwner != address(0), "GroupChat: zero address");
        require(_members[newOwner].active, "GroupChat: not a member");
        _transferOwnership(newOwner);
    }

    function sendMessage(bytes12 iv, bytes calldata senderKey, bytes calldata ciphertext)
        external
        payable
        returns (bytes32 id)
    {
        require(_alive, "GroupChat: dead");
        require(_members[msg.sender].active, "GroupChat: not a member");
        require(msg.value >= fee, "GroupChat: fee too low");
        require(ciphertext.length > 0, "GroupChat: empty message");
        require(senderKey.length == 33, "GroupChat: invalid sender key");

        id = keccak256(abi.encodePacked(_messages.length, iv, senderKey, ciphertext));
        _messages.push(
            Message({
                from: msg.sender, timestamp: block.timestamp, iv: iv, senderKey: senderKey, ciphertext: ciphertext
            })
        );
        emit MessageSent(msg.sender, id, block.timestamp, ciphertext.length);
    }

    function getMessages(uint256 start, uint256 count) external view returns (Message[] memory msgs) {
        if (start >= _messages.length) return new Message[](0);
        uint256 end = start + count;
        if (end > _messages.length) end = _messages.length;
        msgs = new Message[](end - start);
        for (uint256 i = start; i < end; i++) {
            msgs[i - start] = _messages[i];
        }
    }

    function setPublicKey(bytes calldata key, uint8 v, bytes32 r, bytes32 s) external {
        require(key.length == 33, "GroupChat: invalid public key");
        bytes32 msgHash = keccak256(abi.encodePacked(block.chainid, msg.sender, key));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        address recovered = ecrecover(signedHash, v, r, s);
        require(recovered == msg.sender, "GroupChat: not the key owner");
        keys[msg.sender] = key;
        emit PublicKeyRegistered(msg.sender, key);
    }

    function getPublicKey(address who) external view returns (bytes memory) {
        return keys[who];
    }

    /// @notice Owner publishes a wrapped envelope secret for a member (joiners unwrap client-side).
    function setEnvelope(address who, bytes calldata wrapped) external onlyOwner {
        require(_alive, "GroupChat: dead");
        require(who != address(0), "GroupChat: zero address");
        require(wrapped.length > 0, "GroupChat: empty envelope");
        envelopes[who] = wrapped;
        emit EnvelopeSet(who);
    }

    function getEnvelope(address who) external view returns (bytes memory) {
        return envelopes[who];
    }

    function setFee(uint256 newFee) external onlyOwner {
        fee = newFee;
        emit FeeChanged(newFee);
    }

    function withdraw(address to) external onlyOwner {
        require(to != address(0), "GroupChat: zero address");
        uint256 bal = address(this).balance;
        require(bal > 0, "GroupChat: nothing to withdraw");
        (bool ok,) = payable(to).call{value: bal}("");
        require(ok, "GroupChat: withdraw failed");
        emit FeeWithdrawn(to, bal);
    }

    function _addMember(address who) internal {
        _members[who] = MemberInfo({active: true, joinedAt: uint64(block.timestamp)});
        _memberList.push(who);
        emit MemberJoined(who, uint64(block.timestamp));
    }

    function _removeMember(address who) internal {
        _members[who].active = false;
        uint256 n = _memberList.length;
        for (uint256 i = 0; i < n; i++) {
            if (_memberList[i] == who) {
                _memberList[i] = _memberList[n - 1];
                _memberList.pop();
                break;
            }
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
