// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// import "hardhat/console.sol";

contract IOweYou is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    struct IOU {
        string owed;
        address creator;
        bool creatorCompleted;
        bool receiverCompleted;
    }

    event IOUCreated(address indexed created, address indexed receiver, string owed, uint256 tokenId);
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
            createdBalances[iou.creator]--;
            emit IOUCompleted(tokenId);
            delete ious[tokenId];
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

    /** URI HANDLING **/
    string private customBaseURI;

    function setBaseURI(string memory baseURI) external onlyOwner {
        customBaseURI = baseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return customBaseURI;
    }

    constructor(string memory baseURI) ERC721("IOweYou", "IOU") Ownable() {
        customBaseURI = baseURI;
    }
}
