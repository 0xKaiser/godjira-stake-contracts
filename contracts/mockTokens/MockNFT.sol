//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockNFT is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId, 1, "");
    }
}
