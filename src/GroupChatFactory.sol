// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GroupChat} from "./GroupChat.sol";
import {IProPass} from "./IProPass.sol";

/**
 * @title GroupChatFactory
 * @dev Deploys EIP-1167 minimal proxies of a shared GroupChat implementation.
 *      Each clone is a self-managed group; ownership + sole membership go to
 *      the deployer. Factory owner may swap `implementation` for *future*
 *      clones only.
 */
contract GroupChatFactory is Ownable {
    using Clones for address;

    address public implementation;
    IProPass public immutable proPass;

    event GroupCreated(address indexed group, address indexed deployer, string name, uint256 fee);
    event ImplementationUpdated(address indexed implementation);

    constructor(address implementation_, address proPass_) Ownable(msg.sender) {
        require(implementation_ != address(0), "GroupChatFactory: zero impl");
        require(proPass_ != address(0), "GroupChatFactory: zero proPass");
        implementation = implementation_;
        proPass = IProPass(proPass_);
    }

    modifier onlyPro() {
        require(proPass.isPro(msg.sender), "GroupChatFactory: not Pro");
        _;
    }

    function deploy(string calldata name_, uint256 initialFee) external onlyPro returns (address group) {
        group = implementation.clone();
        GroupChat(group).initialize(initialFee, name_, msg.sender);
        emit GroupCreated(group, msg.sender, name_, initialFee);
    }

    function setImplementation(address implementation_) external onlyOwner {
        require(implementation_ != address(0), "GroupChatFactory: zero impl");
        implementation = implementation_;
        emit ImplementationUpdated(implementation_);
    }
}
