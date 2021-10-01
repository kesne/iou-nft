// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "base64-sol/base64.sol";

abstract contract TokenURIGenerator {
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        returns (string memory);
}

abstract contract ReverseRecords {
    function getNames(address[] calldata addresses)
        external
        view
        virtual
        returns (string[] memory r);
}

contract IOweYou is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    struct IOU {
        string owed;
        address creator;
        bool creatorCompleted;
        bool receiverCompleted;
    }

    event IOUCreated(
        address indexed created,
        address indexed receiver,
        string owed,
        uint256 tokenId
    );

    event IOUCompleted(uint256 tokenId);

    mapping(uint256 => IOU) public ious;

    // Mapping from the creator address to the amount of IOUs they've created:
    mapping(address => uint256) private createdBalances;
    // Mapping from creator to list of created IOU IDs
    mapping(address => mapping(uint256 => uint256)) private createdTokens;
    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private createdTokensIndex;

    /**
     * This method creates a new IOU, minted for the receiver.
     * @param receiver The address that the NFT will be minted for.
     * @param owed The thing that is owed. This will be visible on the NFT.
     */
    function create(address receiver, string memory owed)
        external
        returns (uint256)
    {
        require(
            receiver != address(0),
            "You cannot create an IOU for the zero address"
        );
        require(
            _msgSender() != receiver,
            "You cannot make an IOU to yourself."
        );

        // This check actually is nowhere near perfect, as the message can overflow at lengths far smaller than 40.
        // However, this seemed like a sensible limit.
        require(bytes(owed).length < 40, "Owed message is too long");

        // Mint the NFT:
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _safeMint(receiver, tokenId);

        // Keep track of the IOU metadata:
        // NOTE: This is manually unrolled here to save a tiny bit of gas.
        IOU memory iou;
        iou.owed = owed;
        iou.creator = _msgSender();
        ious[tokenId] = iou;

        // Keep track of metadata to allow querying by the creator:
        _addTokenToCreatorEnumeration(_msgSender(), tokenId);

        emit IOUCreated(_msgSender(), receiver, owed, tokenId);

        return tokenId;
    }

    /**
     * Complete and IOU. This function must be called by both parties involved
     * (the current token holder, and the creator) for the IOU to be considered completed.
     * Once the IOU is completed by both parties, the token will be burned.
     * @param tokenId The ID of the token that you wish to consider complete.
     */
    function complete(uint256 tokenId) external returns (bool) {
        IOU storage iou = ious[tokenId];

        require(
            _msgSender() == ownerOf(tokenId) || _msgSender() == iou.creator,
            "You can only complete your own IOU"
        );

        if (ownerOf(tokenId) == _msgSender()) {
            iou.receiverCompleted = true;
        } else {
            iou.creatorCompleted = true;
        }

        // When both parties consider the IOU to be completed, we burn it:
        if (iou.receiverCompleted && iou.creatorCompleted) {
            _burn(tokenId);
            _removeTokenFromCreatorEnumeration(iou.creator, tokenId);
            delete ious[tokenId];
            emit IOUCompleted(tokenId);
            return true;
        }

        return false;
    }

    /**
     * Check for the balance of IOUs that have been created by a specific address.
     */
    function createdBalanceOf(address creator) public view returns (uint256) {
        require(
            creator != address(0),
            "Cannot query for created IOU for zero address."
        );
        return createdBalances[creator];
    }

    /**
     * Get the tokenId that has been created by a specific creator, by the provided index.
     */
    function tokenOfCreatorByIndex(address creator, uint256 index)
        public
        view
        returns (uint256)
    {
        require(
            index < createdBalanceOf(creator),
            "creator index out of bounds"
        );
        return createdTokens[creator][index];
    }

    /**
     * Returns an IOU by the tokenId. Fails if the IOU does not exist.
     */
    function getIOU(uint256 tokenId) public view returns (IOU memory) {
        require(_exists(tokenId), "No token");
        return ious[tokenId];
    }

    /**
     * These functions handle making the creator side of tokens enumerable.
     * This allows apps to enumerate tokens that users own, as well as those that
     * they have created.
     */

    function _addTokenToCreatorEnumeration(address to, uint256 tokenId)
        private
    {
        uint256 length = createdBalances[to];
        createdTokens[to][length] = tokenId;
        createdTokensIndex[tokenId] = length;
        createdBalances[_msgSender()]++;
    }

    function _removeTokenFromCreatorEnumeration(address from, uint256 tokenId)
        private
    {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).
        uint256 lastTokenIndex = createdBalances[from] - 1;
        uint256 tokenIndex = createdTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = createdTokens[from][lastTokenIndex];

            createdTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            createdTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete createdTokensIndex[tokenId];
        delete createdTokens[from][lastTokenIndex];

        createdBalances[from]--;
    }

    /**
     * This allows for resolving an address to an ens name.
     */
    address private reverseRecordsAddress;

    function setReverseRecordsAddress(address addr) external onlyOwner {
        reverseRecordsAddress = addr;
    }

    function getENSName(address addr) private view returns (string memory) {
        address[] memory addrs = new address[](1);
        addrs[0] = addr;
        string[] memory names = ReverseRecords(reverseRecordsAddress).getNames(
            addrs
        );
        return names[0];
    }

    function addressToByteString(address addr)
        private
        pure
        returns (bytes memory)
    {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return str;
    }

    function formatAddress(address addr) private pure returns (string memory) {
        // 0x0000...0000
        string memory newString = new string(13);
        bytes memory byteString = bytes(newString);
        bytes memory addrBytes = addressToByteString(addr);

        byteString[0] = addrBytes[0];
        byteString[1] = addrBytes[1];
        byteString[2] = addrBytes[2];
        byteString[3] = addrBytes[3];
        byteString[4] = addrBytes[4];
        byteString[5] = addrBytes[5];
        byteString[6] = ".";
        byteString[7] = ".";
        byteString[8] = ".";
        byteString[9] = addrBytes[addrBytes.length - 4];
        byteString[10] = addrBytes[addrBytes.length - 3];
        byteString[11] = addrBytes[addrBytes.length - 2];
        byteString[12] = addrBytes[addrBytes.length - 1];

        return string(newString);
    }

    function getENSOrAddress(address addr)
        private
        view
        returns (string memory)
    {
        string memory ensName = getENSName(addr);
        if (bytes(ensName).length == 0) {
            return formatAddress(addr);
        }
        return ensName;
    }

    /**
     * This allows for upgrading the `tokenURI` function in the future.
     */
    address public customTokenURIAddress;

    function setTokenURIAddress(address tokenURIAddress) external onlyOwner {
        customTokenURIAddress = tokenURIAddress;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "No token");

        // If we've set a custom token URI, use that instead of the built-in contract renderer:
        if (customTokenURIAddress != address(0)) {
            return TokenURIGenerator(customTokenURIAddress).tokenURI(tokenId);
        }

        IOU memory iou = ious[tokenId];

        string memory svg = string(
            abi.encodePacked(
                '<svg viewBox="0 0 500 500" preserveAspectRatio="xMinYMin meet" xmlns="http://www.w3.org/2000/svg">',
                '<rect width="100%" height="100%" fill="#263346" />',
                '<text fill="white" font-family="serif" font-size="48" font-weight="bold" x="36" y="76">IOU</text>',
                '<text fill="white" font-family="serif" font-size="18" font-weight="bold" x="36" y="104">',
                getENSOrAddress(iou.creator),
                '</text><text fill="white" font-family="serif" font-size="120" opacity="0.3" font-style="italic" x="10" y="250">&#x201c;</text>',
                '<text fill="white" font-family="serif" font-size="120" opacity="0.3" font-style="italic" x="400" y="470">&#x201d;</text>'
                '<text fill="white" font-family="serif" font-size="22" font-style="italic" text-anchor="middle" x="50%" y="270">',
                iou.owed,
                "</text></svg>"
            )
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "IOU #',
                        Strings.toString(tokenId),
                        '", "description": "You are owed something. Never forget it.", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(svg)),
                        '"}'
                    )
                )
            )
        );

        return string(
            abi.encodePacked("data:application/json;base64,", json)
        );
    }

    constructor(address initialReverseRecordsAddress)
        ERC721("IOweYou", "IOU")
        Ownable()
    {
        reverseRecordsAddress = initialReverseRecordsAddress;
    }
}
