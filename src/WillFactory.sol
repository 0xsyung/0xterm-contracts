// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {WillVault} from "./WillVault.sol";

/**
 * @title WillFactory
 * @dev Deploys EIP-1167 minimal proxies of a shared WillVault implementation.
 *      CREATE2 salt = keccak256(abi.encode(owner)); one vault per owner.
 *      No privileged role over existing vaults — implementation is immutable.
 *
 *      Companion to 0xterm-app Soft ACK #26. Testnets only until audit gate.
 */
contract WillFactory {
    using Clones for address;

    address public immutable implementation;

    mapping(address => address) public vaultOf;

    error ZeroAddress();
    error HeirIsOwner();
    error VaultExists();

    event VaultCreated(
        address indexed owner, address indexed vault, address indexed heir, uint64 delaySeconds
    );

    constructor(address implementation_) {
        if (implementation_ == address(0)) revert ZeroAddress();
        implementation = implementation_;
    }

    function create(address heir, uint64 delaySeconds) external returns (address vault) {
        address owner = msg.sender;
        if (heir == address(0)) revert ZeroAddress();
        if (heir == owner) revert HeirIsOwner();
        if (vaultOf[owner] != address(0)) revert VaultExists();

        bytes32 salt = keccak256(abi.encode(owner));
        vault = implementation.cloneDeterministic(salt);
        vaultOf[owner] = vault;
        WillVault(payable(vault)).initialize(owner, heir, delaySeconds);
        emit VaultCreated(owner, vault, heir, delaySeconds);
    }
}
