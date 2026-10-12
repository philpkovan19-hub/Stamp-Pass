// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title StampPass - Souvenir check-in passport on BOT Chain
contract StampPass is Ownable, ReentrancyGuard, Pausable {
    struct Location {
        address creator;
        string slug;
        string name;
        string description;
        string iconUrl;
        uint256 createdAt;
        address[] stampers;
    }

    uint256 public createFee = 0.001 ether;
    uint256 public stampFee = 0.0005 ether;
    uint256 public creatorShareBps = 5000; // 50%

    uint256 public constant MAX_CREATE_FEE = 1 ether;
    uint256 public constant MAX_STAMP_FEE = 0.1 ether;
    uint256 public constant MAX_CREATOR_SHARE_BPS = 8000;

    uint256 private _locationCount;

    mapping(uint256 => Location) private _locations;
    mapping(bytes32 => uint256) private _slugToId; // 0 = not found (ids are 1-indexed)
    mapping(uint256 => mapping(address => uint256)) private _stampedAt; // 0 = never
    mapping(address => uint256[]) private _userStamps;

    event LocationCreated(
        uint256 indexed locationId,
        address indexed creator,
        string slug,
        string name
    );
    event StampCollected(
        uint256 indexed locationId,
        address indexed user,
        uint256 stamperCountAfter,
        uint256 creatorPaid,
        uint256 platformPaid
    );
    event FeesUpdated(uint256 createFee, uint256 stampFee, uint256 creatorShareBps);
    event FeesWithdrawn(address indexed to, uint256 amount);

    constructor() Ownable(msg.sender) {}

    // ---- Modifiers-lite helpers ----

    function _validSlug(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        if (b.length < 3 || b.length > 32) return false;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            bool ok = (c >= 0x30 && c <= 0x39) // 0-9
                || (c >= 0x61 && c <= 0x7a)    // a-z
                || (c == 0x2d);                 // -
            if (!ok) return false;
        }
        return true;
    }

    function _slugKey(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    // ---- Core ----

    function createLocation(
        string calldata slug,
        string calldata name,
        string calldata description,
        string calldata iconUrl
    ) external payable whenNotPaused nonReentrant returns (uint256 locationId) {
        require(msg.value >= createFee, "fee");
        require(_validSlug(slug), "slug");
        require(bytes(name).length >= 1 && bytes(name).length <= 64, "name");
        require(bytes(description).length <= 256, "desc");
        require(bytes(iconUrl).length <= 256, "icon");

        bytes32 key = _slugKey(slug);
        require(_slugToId[key] == 0, "dup");

        unchecked { _locationCount += 1; }
        locationId = _locationCount;

        Location storage L = _locations[locationId];
        L.creator = msg.sender;
        L.slug = slug;
        L.name = name;
        L.description = description;
        L.iconUrl = iconUrl;
        L.createdAt = block.timestamp;

        _slugToId[key] = locationId;

        emit LocationCreated(locationId, msg.sender, slug, name);
    }

    function collectStamp(uint256 locationId) external payable whenNotPaused nonReentrant {
        require(locationId > 0 && locationId <= _locationCount, "id");
        require(msg.value >= stampFee, "fee");
        require(_stampedAt[locationId][msg.sender] == 0, "have");

        Location storage L = _locations[locationId];
        _stampedAt[locationId][msg.sender] = block.timestamp;
        L.stampers.push(msg.sender);
        _userStamps[msg.sender].push(locationId);

        uint256 creatorCut = (stampFee * creatorShareBps) / 10000;
        uint256 platformCut = stampFee - creatorCut;

        if (creatorCut > 0 && L.creator != address(0)) {
            (bool ok, ) = payable(L.creator).call{value: creatorCut}("");
            require(ok, "pay");
        }
        // platformCut stays in contract for withdraw; refund overpay
        if (msg.value > stampFee) {
            (bool ok2, ) = payable(msg.sender).call{value: msg.value - stampFee}("");
            require(ok2, "refund");
        }

        emit StampCollected(locationId, msg.sender, L.stampers.length, creatorCut, platformCut);
    }

    // ---- Views ----

    function getLocation(uint256 locationId) external view returns (
        address creator,
        string memory slug,
        string memory name,
        string memory description,
        string memory iconUrl,
        uint256 createdAt,
        uint256 stamperCount
    ) {
        Location storage L = _locations[locationId];
        return (L.creator, L.slug, L.name, L.description, L.iconUrl, L.createdAt, L.stampers.length);
    }

    function getLocationBySlug(string calldata slug) external view returns (uint256) {
        return _slugToId[_slugKey(slug)];
    }

    function hasStamp(uint256 locationId, address user) external view returns (bool) {
        return _stampedAt[locationId][user] != 0;
    }

    function getStamperTimestamp(uint256 locationId, address user) external view returns (uint256) {
        return _stampedAt[locationId][user];
    }

    function getStamps(address user) external view returns (uint256[] memory) {
        return _userStamps[user];
    }

    function getStampers(uint256 locationId) external view returns (address[] memory) {
        return _locations[locationId].stampers;
    }

    function stampCount(address user) external view returns (uint256) {
        return _userStamps[user].length;
    }

    function locationCount() external view returns (uint256) {
        return _locationCount;
    }

    /// Newest first. startOffset = 0 => start at newest.
    function getRecent(uint256 startOffset, uint256 limit) external view returns (uint256[] memory) {
        uint256 total = _locationCount;
        if (startOffset >= total || limit == 0) return new uint256[](0);
        uint256 remaining = total - startOffset;
        uint256 n = remaining < limit ? remaining : limit;
        uint256[] memory out = new uint256[](n);
        // newest id = total; skip startOffset newest
        uint256 startId = total - startOffset;
        for (uint256 i = 0; i < n; i++) {
            out[i] = startId - i;
        }
        return out;
    }

    // ---- Admin ----

    function setCreateFee(uint256 v) external onlyOwner {
        require(v <= MAX_CREATE_FEE, "max");
        createFee = v;
        emit FeesUpdated(createFee, stampFee, creatorShareBps);
    }

    function setStampFee(uint256 v) external onlyOwner {
        require(v <= MAX_STAMP_FEE, "max");
        stampFee = v;
        emit FeesUpdated(createFee, stampFee, creatorShareBps);
    }

    function setCreatorShareBps(uint256 v) external onlyOwner {
        require(v <= MAX_CREATOR_SHARE_BPS, "max");
        creatorShareBps = v;
        emit FeesUpdated(createFee, stampFee, creatorShareBps);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "to");
        uint256 bal = address(this).balance;
        require(bal > 0, "empty");
        (bool ok, ) = to.call{value: bal}("");
        require(ok, "send");
        emit FeesWithdrawn(to, bal);
    }

    receive() external payable {}
}
