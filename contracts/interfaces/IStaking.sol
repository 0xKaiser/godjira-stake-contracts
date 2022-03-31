// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IStaking is IERC721Enumerable {
	function stake(uint256[] memory _tokenIds) external;
}
