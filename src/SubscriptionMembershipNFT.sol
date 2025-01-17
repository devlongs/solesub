// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/security/Pausable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/utils/Counters.sol";

/**
 * @title SubscriptionMembershipNFT
 * @notice A soulbound, time-based membership token using ERC721.
 */
contract SubscriptionMembershipNFT is 
    ERC721,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    using Counters for Counters.Counter;

    // ------------------------- ERRORS -------------------------
    error InsufficientFee(uint256 required, uint256 provided);
    error AlreadyHasMembership(address user);
    error NoMembershipToRenew(address user);
    error MembershipTransferNotAllowed();
    error NotTokenOwner();
    error InvalidTokenId();

    // ------------------------- EVENTS -------------------------
    event MembershipPurchased(
        address indexed user,
        uint256 indexed tokenId,
        uint256 expiration
    );
    event MembershipRenewed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 oldExpiration,
        uint256 newExpiration
    );
    event MembershipBurned(
        address indexed user,
        uint256 indexed tokenId
    );
    event MembershipPriceUpdated(
        uint256 oldPrice,
        uint256 newPrice
    );
    event MembershipDurationUpdated(
        uint256 oldDuration,
        uint256 newDuration
    );
    event FundsWithdrawn(address indexed owner, uint256 amount);

    // ------------------------- STATE -------------------------
    /// @dev Incremental token ID counter
    Counters.Counter private _tokenIds;

    /// @notice The cost (in wei) to purchase or renew the membership
    uint256 public membershipPrice;

    /// @notice How long each purchased membership (or renewal) lasts in seconds
    uint256 public membershipDuration;

    /// @notice tokenId -> membership expiration timestamp
    mapping (uint256 => uint256) public membershipExpirations;

    /// @notice address -> owned tokenId (0 if none)
    mapping(address => uint256) public userTokenId;

    // ------------------------- CONSTRUCTOR -------------------------
    /**
     * @param name_                ERC721 name
     * @param symbol_              ERC721 symbol
     * @param _membershipPrice     membership price in wei
     * @param _membershipDuration  membership duration in seconds
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 _membershipPrice,
        uint256 _membershipDuration
    )
        ERC721(name_, symbol_)
    {
        membershipPrice = _membershipPrice;
        membershipDuration = _membershipDuration;
    }

    // ------------------------- EXTERNAL/PUBLIC -------------------------
    function buyMembership() external payable whenNotPaused nonReentrant {
        if (msg.value != membershipPrice) {
            revert InsufficientFee(membershipPrice, msg.value);
        }
        if (userTokenId[msg.sender] != 0) {
            revert AlreadyHasMembership(msg.sender);
        }

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);

        uint256 expiration = block.timestamp + membershipDuration;
        membershipExpirations[newTokenId] = expiration;
        userTokenId[msg.sender] = newTokenId;

        emit MembershipPurchased(msg.sender, newTokenId, expiration);
    }

    function renewMembership() external payable whenNotPaused nonReentrant {
        if (msg.value != membershipPrice) {
            revert InsufficientFee(membershipPrice, msg.value);
        }
        uint256 tokenId = userTokenId[msg.sender];
        if (tokenId == 0) {
            revert NoMembershipToRenew(msg.sender);
        }

        uint256 oldExpiration = membershipExpirations[tokenId];
        uint256 newExpiration = block.timestamp >= oldExpiration
            ? block.timestamp + membershipDuration
            : oldExpiration + membershipDuration;

        membershipExpirations[tokenId] = newExpiration;
        emit MembershipRenewed(msg.sender, tokenId, oldExpiration, newExpiration);
    }

    function hasValidMembership(address user) external view returns (bool) {
        uint256 tokenId = userTokenId[user];
        if (tokenId == 0) return false;
        return block.timestamp < membershipExpirations[tokenId];
    }

    function burnMembership(uint256 tokenId) external nonReentrant {
        address tokenOwner = ownerOf(tokenId);

        if (msg.sender != tokenOwner && msg.sender != owner()) {
            revert NotTokenOwner();
        }

        userTokenId[tokenOwner] = 0;
        membershipExpirations[tokenId] = 0;
        _burn(tokenId);

        emit MembershipBurned(tokenOwner, tokenId);
    }

    // ------------------------- OWNER-ONLY ADMIN -------------------------
    function setMembershipPrice(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = membershipPrice;
        membershipPrice = newPrice;
        emit MembershipPriceUpdated(oldPrice, newPrice);
    }

    function setMembershipDuration(uint256 newDuration) external onlyOwner {
        uint256 oldDuration = membershipDuration;
        membershipDuration = newDuration;
        emit MembershipDurationUpdated(oldDuration, newDuration);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
        emit FundsWithdrawn(owner(), balance);
    }

    // ------------------------- INTERNAL -------------------------
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        if (from != address(0) && to != address(0)) {
            revert MembershipTransferNotAllowed();
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}
