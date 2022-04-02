//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "./interfaces/IJiraToken.sol";
// import "./Whitelist.sol";
import "hardhat/console.sol";

contract Staking is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC721EnumerableUpgradeable, IERC721ReceiverUpgradeable {
// contract Staking is Initializable, WhitelistChecker, ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC721EnumerableUpgradeable, IERC721ReceiverUpgradeable {
	using CountersUpgradeable for CountersUpgradeable.Counter;
	using ECDSAUpgradeable for bytes;
  CountersUpgradeable.Counter private bagIds;

	IERC721Upgradeable public genesis;
	IERC721Upgradeable public gen2;
	IJiraToken public rewardsToken;

	struct StakeInfo {
		uint256 genTokenId;
		uint256 genRarity;
		uint256[] gen2TokenIds;
		uint256[] gen2Rarities;
		uint256 since;
	}

	address private _designatedSigner;

	/// @dev bagId -> Stake info
  mapping(uint256 => StakeInfo) public stakeInfos;

	mapping(address => uint256) private _balances;
	mapping(address => uint256) public claims;
	mapping(uint256 => uint256) public genMultipliers;
	mapping(uint256 => uint256) public gen2Earnings;
	mapping(uint256 => uint256) public gen2RateMultipliers;


	event Staked(address indexed user, uint256 bagId);
	event UnStaked(address indexed user, uint256 bagId, uint256 reward);
	event Claimed(address indexed user, uint256 bagId, uint256 reward);
	event ClaimedAll(address indexed user, uint256 reward);

	function initialize(address _genesis, address _gen2, address _rewardsToken) initializer public {
		// __Whitelist_init();
		__ERC721_init("GenStaking", "GS");
		__Ownable_init();

		genesis = IERC721Upgradeable(_genesis);
		gen2= IERC721Upgradeable(_gen2);
    rewardsToken = IJiraToken(_rewardsToken);

		genMultipliers[1] = 2; // Common
		genMultipliers[2] = 3; // Legendary

		gen2Earnings[1] = 4; // Common
		gen2Earnings[2] = 6; // Rare
		gen2Earnings[3] = 8; // Legendary

		gen2RateMultipliers[1] = 1;
		gen2RateMultipliers[2] = uint256(21) / uint256(20);
		gen2RateMultipliers[3] = uint256(23) / uint256(20);
	}

	function stake(StakeInfo[] memory _stakeInfos) external nonReentrant {
	// function stake(whitelisted memory whitelist) external nonReentrant {
		// console.log(getSigner(whitelist));
		// require(getSigner(whitelist) == designatedSigner,"Invalid signature");
    // require(msg.sender == whitelist.whiteListAddress,"not same user");

		for (uint256 i = 0; i < _stakeInfos.length; i++) {
			if(_stakeInfos[i].genTokenId != 0) {
				require(msg.sender == genesis.ownerOf(_stakeInfos[i].genTokenId), "Not genesis owner");
				genesis.safeTransferFrom(msg.sender, address(this), _stakeInfos[i].genTokenId);
			}

			for (uint256 j = 0; j < _stakeInfos[i].gen2TokenIds.length; j++) {
				uint256 gen2TokenId = _stakeInfos[i].gen2TokenIds[j];
				require(gen2TokenId != 0, "invalid gen2 tokenId");
				require(msg.sender == gen2.ownerOf(gen2TokenId), "Not gen2 owner");
				gen2.safeTransferFrom(msg.sender, address(this), gen2TokenId);
			}

			bagIds.increment();
			uint256 bagId = bagIds.current();
			_safeMint(msg.sender, bagId);

			stakeInfos[bagId] = StakeInfo({
				genTokenId: _stakeInfos[i].genTokenId,
				gen2TokenIds: _stakeInfos[i].gen2TokenIds,
				genRarity: _stakeInfos[i].genRarity,
				gen2Rarities: _stakeInfos[i].gen2Rarities,
				since: block.timestamp
			});
			
			emit Staked(msg.sender,	bagId);
		}
	}

	function unStake(uint256[] memory _bagIds) external nonReentrant {
		uint256[] memory genesisTokenIds = new uint256[](_bagIds.length);
		for (uint256 i = 0; i < _bagIds.length; i++) {
			uint256 bagId = _bagIds[i];
			require(msg.sender == ownerOf(bagId), "Not bag owner");
			uint256 _genesisTokenId = stakeInfos[bagId].genTokenId;
			genesisTokenIds[i] = _genesisTokenId;
			genesis.safeTransferFrom(address(this), msg.sender, _genesisTokenId);
			
			uint256 getReward = getStakeReward();
			if(getReward > 0) {
				rewardsToken.mint(msg.sender, getReward);
			}
			delete stakeInfos[bagId];
			delete claims[msg.sender];
			emit UnStaked(msg.sender, bagId, getReward);
		}
	}

	function claim(uint256 _bagId, uint256 _amount) external nonReentrant {
		require(msg.sender == ownerOf(_bagId), "Not owner");
		uint256  stakeReward = _calculateStakeReward(_bagId) - claims[msg.sender];
		require(_amount != 0, "Invalid amount");
		require(stakeInfos[_bagId].gen2TokenIds.length != 0, "No stake");
		require(stakeReward >= _amount, "Cannot claim more than you own");
		claims[msg.sender] += _amount;
		rewardsToken.mint(msg.sender, _amount);
		emit Claimed(msg.sender, _bagId, _amount);
	}

	function claimAll() external nonReentrant {
		uint256 _amount = getStakeReward();
		require(_amount != 0, "Invalid amount");
		rewardsToken.mint(msg.sender, _amount);
		claims[msg.sender] += _amount;
		emit ClaimedAll(msg.sender, _amount);
	}

	function _calculateStakeReward(uint256 _bagId) internal view returns (uint256) {
		uint256 period = ((block.timestamp - stakeInfos[_bagId].since) / 1 days);
		uint256 baseEarning = 0;
		uint256 gen2TokenLen = stakeInfos[_bagId].gen2TokenIds.length;
		uint256 genesisRateMultiplier = 1;

		if(stakeInfos[_bagId].genRarity != 0) {
			genesisRateMultiplier = genMultipliers[stakeInfos[_bagId].genRarity];
		}

		for(uint256 i = 0; i < stakeInfos[_bagId].gen2Rarities.length; i++ ) {
			baseEarning += gen2Earnings[stakeInfos[_bagId].gen2Rarities[i]];
		}

		uint256 total = 0;
		if(gen2TokenLen <= 1) {
			total = baseEarning * genesisRateMultiplier * period;
		}
		else if(gen2TokenLen == 2) {
			total = (baseEarning * genesisRateMultiplier * period) * 21 / 20 ;
		}
		else if(gen2TokenLen == 3) {
			total = (baseEarning * genesisRateMultiplier * period) * 23 / 20 ;
		} 

    return total;
  }

	function getStakeReward() public view returns (uint256) {
		uint256 bags = balanceOf(msg.sender);
		uint256 totalReward = 0;
		for(uint256 i = 0; i < bags; i++ ) {
			uint256 bagId = tokenByIndex(i);
			if(stakeInfos[bagId].since > 0) {
				totalReward += _calculateStakeReward(bagId) - claims[msg.sender];
			}
		}

		return totalReward;
  }

	function modifySigner(address _signer) external onlyOwner {
		_designatedSigner = _signer;
	}

	function designatedSigner() external view onlyOwner returns (address) {
		return _designatedSigner;
	}

	function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
		return this.onERC721Received.selector;
	}
}