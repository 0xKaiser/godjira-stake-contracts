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
import "hardhat/console.sol";

contract Staking is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC721EnumerableUpgradeable, IERC721ReceiverUpgradeable {
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
		uint256 reward;
		uint256 since;
	}

	address private _designatedSigner;

	/// @dev bagId -> Stake info
  mapping(uint256 => StakeInfo) public stakeInfos;

	/// @dev gen token id => bag id
  mapping(uint256 => uint256) public genBagIds;
  /// @dev gen2 token id => bag id
  mapping(uint256 => uint256) public gen2BagIds;

	mapping(address => uint256) private _balances;
	mapping(address => uint256) public claims;
	mapping(uint256 => uint256) public claimBags;
	mapping(uint256 => uint256) public genMultipliers;
	mapping(uint256 => uint256) public gen2Earnings;
	mapping(uint256 => uint256) public gen2RateMultipliers;


	event Staked(address indexed user, uint256 bagId);
	event UnStaked(address indexed user, uint256 bagId, uint256 reward);
	event Claimed(address indexed user, uint256 bagId, uint256 reward);
	event AddBagInfo(address indexed user, uint256 bagId);
	event ClaimedAll(address indexed user, uint256 reward);

	function initialize(address _genesis, address _gen2, address _rewardsToken) initializer public {
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
		for (uint256 i = 0; i < _stakeInfos.length; i++) {
			if(_stakeInfos[i].genTokenId != 0) {
				require(msg.sender == genesis.ownerOf(_stakeInfos[i].genTokenId), "Not genesis owner");
				genesis.safeTransferFrom(msg.sender, address(this), _stakeInfos[i].genTokenId);
			}
			
			uint256 _gen2TokenCount = _stakeInfos[i].gen2TokenIds.length;
			require(_gen2TokenCount <= 3, "Gen2 shouldn't be more than 3");
			
			bagIds.increment();
			uint256 bagId = bagIds.current();
			_safeMint(msg.sender, bagId);
			
			if(_stakeInfos[i].genTokenId != 0) {
				genBagIds[_stakeInfos[i].genTokenId] = bagId;
			}

			for (uint256 j = 0; j < _gen2TokenCount; j++) {
				uint256 gen2TokenId = _stakeInfos[i].gen2TokenIds[j];
				require(gen2TokenId != 0, "invalid gen2 tokenId");
				require(msg.sender == gen2.ownerOf(gen2TokenId), "Not gen2 owner");
				gen2BagIds[gen2TokenId] = bagId;
				gen2.safeTransferFrom(msg.sender, address(this), gen2TokenId);
			}

			stakeInfos[bagId] = StakeInfo({
				genTokenId: _stakeInfos[i].genTokenId,
				gen2TokenIds: _stakeInfos[i].gen2TokenIds,
				genRarity: _stakeInfos[i].genRarity,
				gen2Rarities: _stakeInfos[i].gen2Rarities,
				reward: 0,
				since: block.timestamp
			});
			
			emit Staked(msg.sender,	bagId);
		}
	}

	function addBagInfo(
		uint256 _bagId,
		uint256 _genTokenId,
		uint256[] memory _gen2TokenIds,
		uint256[] memory _gen2Rarities
	) external nonReentrant {
		uint256 exsistGen2Count = stakeInfos[_bagId].gen2TokenIds.length;
		uint256 _gen2Count = _gen2TokenIds.length;
		require(_gen2Count == _gen2Rarities.length);
		require((exsistGen2Count + _gen2Count) <= 3, "Can't add gen2 more than 3");
		
		if(stakeInfos[_bagId].genTokenId == 0) {
			stakeInfos[_bagId].genTokenId = _genTokenId;
		}
		uint256 getReward = _calculateStakeReward(_bagId) - claimBags[_bagId];
		stakeInfos[_bagId].reward += getReward;
		for (uint256 i = 0; i < _gen2Count; i++) {
			stakeInfos[_bagId].gen2TokenIds.push(_gen2TokenIds[i]);
			stakeInfos[_bagId].gen2Rarities.push(_gen2Rarities[i]);
		}
		emit AddBagInfo(msg.sender, _bagId);
	}

	function unStake(uint256 _genTokenId, uint256[] memory _gen2TokenIds) external nonReentrant {
		uint256 gen2TokenCount = _gen2TokenIds.length;
		require(_genTokenId != 0 || gen2TokenCount != 0, "Invalid args");

		if(_genTokenId != 0) {
			uint256 bagId = genBagIds[_genTokenId];
			require(msg.sender == ownerOf(bagId), "Not bag owner");
			genesis.safeTransferFrom(address(this), msg.sender, _genTokenId);
			stakeInfos[bagId].genTokenId = 0;
		}

		if(gen2TokenCount != 0) {
			for(uint256 i = 0; i < gen2TokenCount; i++ ) {
				uint256 bagId = gen2BagIds[_gen2TokenIds[i]];
				if(bagId == 0) continue;
				require(msg.sender == ownerOf(bagId), "Not bag owner");

				uint256 bagGen2TokenCount = stakeInfos[bagId].gen2TokenIds.length;
				for(uint256 j = 0; j < bagGen2TokenCount; j++ ) {
					if(stakeInfos[bagId].gen2TokenIds[j] == _gen2TokenIds[i]) {
						gen2.safeTransferFrom(address(this), msg.sender, _gen2TokenIds[i]);
						uint256 getReward = _calculateStakeReward(bagId) - claimBags[bagId];
						if(getReward > 0) {
							rewardsToken.mint(msg.sender, getReward);
							claimBags[bagId] += getReward;
						}

						stakeInfos[bagId].reward = 0;
						stakeInfos[bagId].since = block.timestamp;

						emit UnStaked(msg.sender, bagId, getReward);

						delete claimBags[bagId];
						delete gen2BagIds[_gen2TokenIds[i]];

						if(j == 2) {
							stakeInfos[bagId].gen2TokenIds.pop();
							stakeInfos[bagId].gen2Rarities.pop();
						}
						else {
							stakeInfos[bagId].gen2TokenIds[j] = stakeInfos[bagId].gen2TokenIds[bagGen2TokenCount - 1];
							stakeInfos[bagId].gen2TokenIds.pop();
							stakeInfos[bagId].gen2Rarities[j] = stakeInfos[bagId].gen2Rarities[bagGen2TokenCount - 1];
							stakeInfos[bagId].gen2Rarities.pop();
							bagGen2TokenCount--;
						}

						if(bagGen2TokenCount == 0 && stakeInfos[bagId].genTokenId == 0) {
							delete stakeInfos[bagId];
							delete claimBags[bagId];
							_burn(bagId);
						}
						break;
					}
				}
			}
		}
	}

	function claim(uint256 _bagId, uint256 _amount) external nonReentrant {
		require(msg.sender == ownerOf(_bagId), "Not owner");
		uint256  stakeReward = _calculateStakeReward(_bagId) - claimBags[_bagId];
		require(_amount != 0, "Invalid amount");
		require(stakeInfos[_bagId].gen2TokenIds.length != 0, "No stake");
		require(stakeReward >= _amount, "Cannot claim more than you own");
		claimBags[_bagId] += _amount;
		rewardsToken.mint(msg.sender, _amount);
		emit Claimed(msg.sender, _bagId, _amount);
	}

	function claimAll() external nonReentrant {
		uint256 _amount = getStakeReward();
		require(_amount != 0, "Invalid amount");
		rewardsToken.mint(msg.sender, _amount);

		uint256 bags = balanceOf(msg.sender);
		for(uint256 i = 0; i < bags; i++ ) {
			uint256 bagId = tokenByIndex(i);
			if(stakeInfos[bagId].since > 0) {
				claimBags[bagId] = _calculateStakeReward(bagId);
			}
		}

		emit ClaimedAll(msg.sender, _amount);
	}

	function _calculateStakeReward(uint256 _bagId) internal view returns (uint256) {
		uint256 total = 0;
		if(stakeInfos[_bagId].since == 0) {
			return total;
		}
		uint256 period = ((block.timestamp - stakeInfos[_bagId].since) / 1 days);
		uint256 baseEarning = 0;
		uint256 gen2TokenLen = stakeInfos[_bagId].gen2TokenIds.length;
		uint256 genesisRateMultiplier = 1;
		uint256 reward = stakeInfos[_bagId].reward;

		if(stakeInfos[_bagId].genRarity != 0) {
			genesisRateMultiplier = genMultipliers[stakeInfos[_bagId].genRarity];
		}

		for(uint256 i = 0; i < stakeInfos[_bagId].gen2Rarities.length; i++ ) {
			baseEarning += gen2Earnings[stakeInfos[_bagId].gen2Rarities[i]];
		}

		if(gen2TokenLen <= 1) {
			total = baseEarning * genesisRateMultiplier * period + reward;
		}
		else if(gen2TokenLen == 2) {
			total = (baseEarning * genesisRateMultiplier * period) * 21 / 20 + reward;
		}
		else if(gen2TokenLen == 3) {
			total = (baseEarning * genesisRateMultiplier * period) * 23 / 20 + reward;
		} 

    return total;
  }

	function getStakeReward() public view returns (uint256) {
		uint256 bags = balanceOf(msg.sender);
		uint256 totalReward = 0;
		for(uint256 i = 0; i < bags; i++ ) {
			uint256 bagId = tokenByIndex(i);
			if(stakeInfos[bagId].since > 0) {
				totalReward += _calculateStakeReward(bagId) - claimBags[bagId];
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