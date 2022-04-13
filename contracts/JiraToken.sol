// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract JiraToken is ERC20, Ownable {
    using SafeMath for uint256;

    address public staking; //TODO : Set Address
    uint8 public _decimals = 18;
    string public _name = 'Jira Token';
    string public _symbol = 'JIRA';
    uint256 TOTAL_CAP = 2 * 10 ** 8 * 1e18;
    uint256 STAKING_CAP = 10 ** 7 * 1e18;
    uint256 stakingSupply = 0;

    constructor() ERC20(_name, _symbol) {

    }

    modifier onlyStaking() {
        require(msg.sender == staking, "Not staking");
        _;
    }
    
    function mint(address _to, uint256 _amount) external onlyStaking {
        require(_amount != 0, "Invalid amount");
        require(stakingSupply + _amount <= STAKING_CAP, "Max limit");
	    stakingSupply += _amount;
        _mint(_to, _amount);
    }

    function mintOnlyOwner(address _to, uint256 _amount) external onlyOwner {
        require(_amount != 0, "Invalid amount");
        require(totalSupply() + _amount <= TOTAL_CAP, "Max limit");
        _mint(_to, _amount);
    }

    function modifyTotalCap(uint256 _cap) external onlyOwner {
	require(_cap > totalSupply(), "total supply already exceeds");
	TOTAL_CAP = _cap;
    }

    function modifyStakingCap(uint256 _cap) external onlyOwner {
	require(_cap > stakeSupply(), "staking supply already exceeds");
	STAKING_CAP = _cap;
    }

    function modifyStakingOwner(address _staking) external onlyOwner {
        staking = _staking;
    }

    function stakeSupply() public view returns (uint256) {
	return stakingSupply;
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
