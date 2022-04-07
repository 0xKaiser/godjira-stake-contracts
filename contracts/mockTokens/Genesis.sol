//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract Genesis is ERC721Enumerable, Ownable, ReentrancyGuard {
    /// @dev Maximum elements
    uint256 CAP = 333;

    /// @dev baseTokenURI
    string public baseTokenURI;

    event Mint(address indexed to, uint256[] _tokens);

    event SetBaseTokenURI(string baseTokenURI);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseToken
    ) ERC721(_name, _symbol) {
        setBaseURI(_baseToken);
    }

    /**
     * @dev Mint NFTs
     */

    function mint(uint256[] memory _tokens) external nonReentrant {
        require(_tokens.length > 0, "genesis : mint amount invalid");
        require(totalSupply() + _tokens.length <= CAP, "genesis : max limit");

        for (uint256 i = 0; i < _tokens.length; i++) {
            _safeMint(msg.sender, _tokens[i]);
        }

        emit Mint(msg.sender, _tokens);
    }

    /**
     * @dev Get `baseTokenURI`
     * Overrided
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    /**
     * @dev Set `baseTokenURI`
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        require(bytes(baseURI).length > 0, "genesis : base URI invalid");
        baseTokenURI = baseURI;

        emit SetBaseTokenURI(baseURI);
    }
}
