//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Gen2 is ERC721A, Ownable {
    /// @dev baseTokenURI
    string public baseTokenURI;

    address public constant CORE_TEAM_ADDRESS = 0xC79b099E83f6ECc8242f93d35782562b42c459F3;
    address public constant FOUNDER_SHAN_ADDRESS = 0xAd7Bbe006c8D919Ffcf6148b227Bb692F7D1fbc7;
    address public constant FOUNDER_JAMIE_ADDRESS = 0x2dFa24018E419eA8453190155434D35328A8c6d8;

    address public gen2Sale;

    event SetBaseTokenURI(string baseTokenURI);
    event SetGen2Sale(address _gen2Sale);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory baseToken_
    ) ERC721A(_name, _symbol) {
        setBaseURI(baseToken_);
    }

    function mint(uint256 _amount) external {
        _safeMint(msg.sender, _amount);
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
        require(bytes(baseURI).length > 0, "gen2.setBaseURI: base URI invalid");
        baseTokenURI = baseURI;

        emit SetBaseTokenURI(baseURI);
    }

    function setGen2Sale(address _gen2Sale) external onlyOwner {
        require(_gen2Sale != address(0), "gen2.setGen2Sale: address invalid");
        gen2Sale = _gen2Sale;

        emit SetGen2Sale(_gen2Sale);
    }
    
    /**
     * @dev Override {ERC721A-isApprovedForAll}.
     */
     function isApprovedForAll(
         address _owner, 
         address _operator
    ) public view virtual override returns (bool) {
        if (_owner == CORE_TEAM_ADDRESS && _operator == gen2Sale) {
            return true;
        }
        return ERC721A.isApprovedForAll(_owner, _operator);
    }
}
