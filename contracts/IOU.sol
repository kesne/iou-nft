// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract IOweYou is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    struct IOU {
        string owed;
        address creator;
        address receiver;
        bool creatorCompleted;
        bool receiverCompleted;
    }

    mapping(uint256 => IOU) public ious;

    function create(address receiver, string memory owed)
        public
        returns (uint256)
    {
        require(
            _msgSender() != receiver,
            "You cannot make an IOU to yourself."
        );

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(receiver, newItemId);

        ious[newItemId] = IOU(owed, _msgSender(), receiver, false, false);

        return newItemId;
    }

    function complete(uint256 tokenId) public returns (bool) {
        IOU storage iou = ious[tokenId];
        require(
            _msgSender() == iou.receiver || _msgSender() == iou.creator,
            "You can only complete your own IOU"
        );

        if (iou.receiver == _msgSender()) {
            iou.receiverCompleted = true;
        } else {
            iou.creatorCompleted = true;
        }

        // When both parties consider the IOU to be completed, we burn it:
        if (iou.receiverCompleted && iou.creatorCompleted) {
            _burn(tokenId);
						delete ious[tokenId];
            return true;
        }

        return false;
    }

    function getIOU(uint256 tokenId) public view returns (IOU memory) {
        IOU memory iou = ious[tokenId];

        // In the event that the IOUs has not yet been created, the null address
        // will be returned as the creator, so we can use that to gate this.
        require(iou.creator != address(0), "IOU does not exist.");

        return iou;
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
