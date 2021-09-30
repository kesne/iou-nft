// SPDX-License-Identifier: MIT
// This is a test tokenURI-compatible contract that is used to test the tokenURI
// upgrading mechanism in the core contract.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";

contract TestTokenURI {
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "Static Token URI For: ",
                    Strings.toString(tokenId)
                )
            );
    }

    constructor() {}
}
