// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    ERC721EnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ProPass
 * @dev Expirable, transferable ERC-721 Pro membership (Soft ACK #139 slice 1).
 *      UUPS + Ownable. Each `purchase(periods)` always mints a NEW tokenId with
 *      an immutable `expiresAt`. `isPro(account)` is true iff any owned token
 *      still has expiresAt > block.timestamp. Expired tokens are never auto-burned.
 *
 *      Deploy behind ERC1967Proxy (see DeployProPass.s.sol / ProPassDeploy.md).
 *      Soft ACK #139 Lock I: on-chain data:application/json;base64 tokenURI.
 *      Soft ACK MetaMask IMAGE_URI: dedicated PNG (not logo.svg) —
 *      https://0xterm.xyz/propass.png (Soft ACK Design 6357300710).
 */
contract ProPass is Initializable, ERC721EnumerableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// Max periods purchasable in a single tx (Soft ACK lock).
    uint256 public constant MAX_PERIODS = 24;

    /// Dedicated MetaMask-safe ProPass image (Soft ACK Design — PNG, explicit colors).
    string public constant IMAGE_URI = "https://0xterm.xyz/propass.png";

    uint256 public pricePerPeriod;
    uint64 public periodSeconds;

    uint256 private _nextTokenId; // 1-based; 0 reserved / unused
    mapping(uint256 tokenId => uint64) private _expiresAt;

    event Purchased(address indexed buyer, uint256 indexed tokenId, uint256 periods, uint256 paid, uint64 expiresAt);
    event PricePerPeriodChanged(uint256 newPrice);
    event Withdrawn(address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param pricePerPeriod_ ETH price for one period (Sepolia Soft ACK default: 0.01 ether)
     * @param periodSeconds_  length of one period in seconds (Soft ACK: 30 days)
     */
    function initialize(uint256 pricePerPeriod_, uint64 periodSeconds_) public initializer {
        require(periodSeconds_ > 0, "ProPass: bad period");
        __ERC721_init("0xterm Pro", "PRO");
        __ERC721Enumerable_init();
        __Ownable_init(msg.sender);
        pricePerPeriod = pricePerPeriod_;
        periodSeconds = periodSeconds_;
        _nextTokenId = 1;
    }

    /**
     * @notice Pay exact ETH for `periods` and mint a new ProPass NFT.
     *         Expiry is fixed at mint: block.timestamp + periods * periodSeconds.
     */
    function purchase(uint256 periods) external payable returns (uint256 tokenId) {
        require(periods > 0 && periods <= MAX_PERIODS, "ProPass: bad periods");
        uint256 cost = pricePerPeriod * periods;
        require(msg.value == cost, "ProPass: wrong ETH");

        tokenId = _nextTokenId++;
        uint64 exp = uint64(block.timestamp + uint256(periods) * uint256(periodSeconds));
        _expiresAt[tokenId] = exp;
        _safeMint(msg.sender, tokenId);

        emit Purchased(msg.sender, tokenId, periods, msg.value, exp);
    }

    /// Immutable after mint. Reverts if token does not exist.
    function expiresAt(uint256 tokenId) external view returns (uint64) {
        _requireOwned(tokenId);
        return _expiresAt[tokenId];
    }

    /// True iff the account owns at least one non-expired pass.
    function isPro(address account) external view returns (bool) {
        uint256 bal = balanceOf(account);
        for (uint256 i = 0; i < bal; i++) {
            uint256 id = tokenOfOwnerByIndex(account, i);
            if (_expiresAt[id] > block.timestamp) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice ERC-721 metadata as on-chain `data:application/json;base64,...`.
     *         Shared IMAGE_URI for all tokens; optional `expiresAt` attribute (unix).
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint64 exp = _expiresAt[tokenId];
        string memory json = string(
            abi.encodePacked(
                '{"name":"0xterm Pro #',
                Strings.toString(tokenId),
                '","description":"0xterm Pro membership. Hold any non-expired pass for Pro access on 0xterm.",',
                '"image":"',
                IMAGE_URI,
                '","attributes":[{"trait_type":"expiresAt","display_type":"date","value":',
                Strings.toString(uint256(exp)),
                "}]}"
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function setPricePerPeriod(uint256 newPrice) external onlyOwner {
        pricePerPeriod = newPrice;
        emit PricePerPeriodChanged(newPrice);
    }

    function withdraw(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "ProPass: zero to");
        require(amount > 0 && amount <= address(this).balance, "ProPass: bad amount");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ProPass: withdraw failed");
        emit Withdrawn(to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
