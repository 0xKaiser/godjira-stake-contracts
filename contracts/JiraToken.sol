// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract JiraToken is ERC20, Ownable {
    using SafeMath for uint256;

    address staking; //TODO : Set Address
    uint8 public _decimals = 18;
    string public _name = 'Jira Token';
    string public _symbol = 'JIRA';
    uint256 CAP = 2 * 10 ** 8 * 1e18;

    constructor() ERC20(_name, _symbol) {

    }

    modifier onlyStaking() {
        require(msg.sender == staking, "Not staking");
        _;
    }
    
    function mint(address _to, uint256 _amount) external onlyStaking {
        require(_amount != 0, "Invalid amount");
        require(totalSupply() + _amount <= CAP, "Max limit");
        _mint(_to, _amount);
    }

    function mintOnlyOwner(address _to, uint256 _amount) external onlyOwner {
        require(_amount != 0, "Invalid amount");
        require(totalSupply() + _amount <= CAP, "Max limit");
        _mint(_to, _amount);
    }

    function modifyStakingOwner(address _staking) external onlyOwner {
        staking = _staking;
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }
}
