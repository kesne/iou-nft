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

    function create(address receiver, string memory owed)
        public
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

        // Mint the NFT:
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _safeMint(receiver, tokenId);

        // Keep track of the IOU metadata:
        IOU memory iou;
        iou.owed = owed;
        iou.creator = _msgSender();
        ious[tokenId] = iou;

        // Keep track of metadata to allow querying by the creator:
        _addTokenToCreatorEnumeration(_msgSender(), tokenId);

        emit IOUCreated(_msgSender(), receiver, owed, tokenId);

        return tokenId;
    }

    function complete(uint256 tokenId) public returns (bool) {
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
            // TODO: Move this to the remove function:
            createdBalances[iou.creator]--;
            delete ious[tokenId];
            emit IOUCompleted(tokenId);
            return true;
        }

        return false;
    }

    function createdBalanceOf(address creator) public view returns (uint256) {
        require(
            creator != address(0),
            "Cannot query for created IOU for zero address."
        );
        return createdBalances[creator];
    }

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

    function getIOU(uint256 tokenId) public view returns (IOU memory) {
        IOU memory iou = ious[tokenId];

        // In the event that the IOUs has not yet been created, the null address
        // will be returned as the creator, so we can use that to gate this.
        require(iou.creator != address(0), "IOU does not exist.");

        return iou;
    }

    /**
     * @dev These functions handle making the creator side of tokens enumerable.
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
    }

    /**
     * This allows for resolving an address to an ens name.
     */
    address private reverseRecordsAddress;

    function setReverseRecordsAddress(address addr) external onlyOwner {
        reverseRecordsAddress = addr;
    }

    function getENSName(address addr) public view returns (string memory) {
        address[] memory addrs = new address[](1);
        addrs[0] = addr;
        string[] memory names = ReverseRecords(reverseRecordsAddress).getNames(addrs);
        return names[0];
    }

    /**
     * This allows for upgrading the `tokenURI` function in the future.
     */
    address public customTokenURIAddress;

    function setTokenURIAddress(address tokenURIAddress) external onlyOwner {
        customTokenURIAddress = tokenURIAddress;
    }

    function addressToByteString(address addr)
        internal
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

    function addrToString(address addr) public pure returns (string memory) {
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
        // string[17] memory parts;
        // parts[
        //     0
        // ] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-weight: bold; font-family: "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="50%" y="90" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[1] = "foo";

        // parts[
        //     2
        // ] = '</text><text x="50%" y="120" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[3] = "foo";

        // parts[
        //     4
        // ] = '</text><text x="50%" y="150" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[5] = "foo";

        // parts[
        //     6
        // ] = '</text><text x="50%" y="180" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[7] = "foo";

        // parts[
        //     8
        // ] = '</text><text x="50%" y="210" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[9] = "foo";

        // parts[
        //     10
        // ] = '</text><text x="50%" y="240" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[11] = "foo";

        // parts[
        //     14
        // ] = '</text><text x="50%" y="270" dominant-baseline="middle" text-anchor="middle" class="base">';

        // parts[15] = "foo";

        // parts[16] = "</text></svg>";

        // string memory output = string(
        //     abi.encodePacked(
        //         parts[0],
        //         parts[1],
        //         parts[2],
        //         parts[3],
        //         parts[4],
        //         parts[5],
        //         parts[6],
        //         parts[7],
        //         parts[8]
        //     )
        // );
        // output = string(
        //     abi.encodePacked(
        //         output,
        //         parts[9],
        //         parts[10],
        //         parts[11],
        //         parts[12],
        //         parts[13],
        //         parts[14],
        //         parts[15],
        //         parts[16]
        //     )
        // );

        string memory output = "start";

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "TechStack #',
                        Strings.toString(tokenId),
                        '", "description": "Your very own unique TechStack which represents you.", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(output)),
                        '"}'
                    )
                )
            )
        );

        output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    // function tokenURI(uint256 tokenId)
    //     public
    //     view
    //     override
    //     returns (string memory)
    // {
    //     require(_exists(tokenId), "No token");

    //     return
    //         Encoder.encodeMetadataJSON(
    //             Encoder.createMetadataJSON(
    //                 name(),
    //                 "A description",
    //                 "metadata",
    //                 tokenId
    //             )
    //         );
    // }

    constructor(
        address initialReverseRecordsAddress
    ) ERC721("IOweYou", "IOU") Ownable() {
        reverseRecordsAddress = initialReverseRecordsAddress;
    }
}
