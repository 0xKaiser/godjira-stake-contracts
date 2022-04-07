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

	struct Bag {
		uint256 genTokenId;
		uint256 genRarity;
		uint256[] gen2TokenIds;
		uint256[] gen2Rarities;
		uint256 unclaimedBalance;
		uint256 lastStateChange;
	}

	struct genTokenId {
		uint256 id;
	}

	struct gen2TokenId {
		uint256[] ids;
	}

	address private _designatedSigner;

	/// @dev bagId -> Stake info
  mapping(uint256 => Bag) public bags;

	/// @dev gen token id => bag id
  mapping(uint256 => uint256) public genBagIds;
  /// @dev gen2 token id => bag id
  mapping(uint256 => uint256) public gen2BagIds;

	mapping(uint256 => uint256) public claimBags;
	mapping(uint256 => uint256) public genMultipliers;
	mapping(uint256 => uint256) public gen2Earnings;

	event Staked(address indexed user, uint256 bagId);
	event UnStaked(address indexed user, uint256 bagId, uint256 reward);
	event Claimed(address indexed user, uint256 bagId, uint256 reward);
	event AddBagInfo(address indexed user, uint256 bagId);

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
	}

	function stake(
		Bag[] memory _bags,
		bool[] memory isNew,
		uint256[] memory _bagIds
	) external nonReentrant {
		uint256 totalBags = _bagIds.length;
		require(totalBags == _bags.length);
		require(totalBags == isNew.length);

		for (uint256 i = 0; i < _bags.length; i++) {
			if (isNew[i]) {
				_addNewBag(_bags[i].genTokenId, _bags[i].genRarity, _bags[i].gen2TokenIds, _bags[i].gen2Rarities);
			}
			else {
				_addToBag(_bagIds[i], _bags[i].genTokenId, _bags[i].genRarity, _bags[i].gen2TokenIds, _bags[i].gen2Rarities);
			}
		}
	}

	function _addNewBag(
		uint256 _genTokenId,
		uint256 _genTokenRarity,
		uint256[] memory _gen2TokenIds,
		uint256[] memory _gen2Rarities
	) internal {
		uint256 _gen2TokenCount = _gen2TokenIds.length;
		require(_gen2TokenIds.length <= 3, "can't add more than 3 gen2s");
				
		bagIds.increment();
		uint256 bagId = bagIds.current();
				
		if(_isValidGenesisId(_genTokenId)) {
			require(msg.sender == genesis.ownerOf(_genTokenId), "not owner of the genesis");
			require(genBagIds[_genTokenId] == 0, "genesis is already staked");
			genesis.safeTransferFrom(msg.sender, address(this), _genTokenId);
			genBagIds[_genTokenId] = bagId;
		}

		for (uint256 i = 0; i < _gen2TokenCount; i++) {
			require(msg.sender == gen2.ownerOf(_gen2TokenIds[i]), "you don't own this gen2");
			require(gen2BagIds[_gen2TokenIds[i]] == 0, "gen2 is already staked");
			gen2.safeTransferFrom(msg.sender, address(this), _gen2TokenIds[i]);
			gen2BagIds[_gen2TokenIds[i]] = bagId;
		}

		bags[bagId] = Bag({
			genTokenId: _genTokenId,
			gen2TokenIds: _gen2TokenIds,
			genRarity: _genTokenRarity,
			gen2Rarities: _gen2Rarities,
			unclaimedBalance: 0,
			lastStateChange: block.timestamp
		});
		_safeMint(msg.sender, bagId);
	
		emit Staked(msg.sender, bagId);                  
	}

	function _addToBag(
		uint256 _bagId,
		uint256 _genTokenId,
		uint256 _genTokenRarity,
		uint256[] memory _gen2TokenIds,
		uint256[] memory _gen2Rarities
	) internal {
		require(msg.sender == ownerOf(_bagId), "you cannot add to this bag");

		uint256 currentGen2Count = bags[_bagId].gen2TokenIds.length;
		uint256 _gen2Count = _gen2TokenIds.length;
		
		require(_isValidGenesisId(_genTokenId) || _gen2Count != 0, "nothing to add");
		require((currentGen2Count + _gen2Count) <= 3, "can't add more than 3 gen2s");
		
		uint256 _unclaimed = _calculateStakeReward(_bagId);
		bags[_bagId].unclaimedBalance += _unclaimed;
		if (_isValidGenesisId(_genTokenId)) {
			require(genBagIds[_genTokenId] == 0, "genesis is already staked");
			require(_isValidGenesisId(bags[_bagId].genTokenId) != true, "bag already has a genesis");
			bags[_bagId].genTokenId = _genTokenId;
			bags[_bagId].genRarity = _genTokenRarity;
			genBagIds[_genTokenId] = _bagId;
		}
				
		for (uint256 i = 0; i < _gen2Count; i++) {
			require(_isValidGen2Id(_gen2TokenIds[i]), "invalid gen2 token");
			require(gen2BagIds[_gen2TokenIds[i]] == 0, "gen2 is already staked");
			bags[_bagId].gen2TokenIds.push(_gen2TokenIds[i]);
			bags[_bagId].gen2Rarities.push(_gen2Rarities[i]);
			gen2BagIds[_gen2TokenIds[i]] = _bagId;
		}
				
		bags[_bagId].lastStateChange = block.timestamp;
		emit AddBagInfo(msg.sender, _bagId);
	}

	function unstake(
		uint256[] memory _bagIds,
		genTokenId[] memory _genTokenIds,
		gen2TokenId[] memory _gen2TokenIds
	) external nonReentrant {
		uint256 totalBags = _bagIds.length;
		require(totalBags == _genTokenIds.length);
		require(totalBags == _gen2TokenIds.length);
		for (uint256 i = 0; i < totalBags; i++) {
			uint256 _bagId = _bagIds[i];
			require(msg.sender == ownerOf(_bagId), "this bag does not belong to you");
			require(_isValidGenesisId(_genTokenIds[i].id) || _gen2TokenIds[i].ids.length != 0, "nothing to unstake");

			uint256 _unclaimed = _calculateStakeReward(_bagId);
			bags[_bagId].unclaimedBalance += _unclaimed;

			if (_isValidGenesisId(_genTokenIds[i].id)) {
				require(genBagIds[_genTokenIds[i].id] == _bagId, "genesis not found in the bag");
				genesis.safeTransferFrom(address(this), msg.sender, _genTokenIds[i].id);
				bags[_bagIds[i]].genTokenId = 0;
				bags[_bagIds[i]].genRarity = 0;
				delete genBagIds[_genTokenIds[i].id];
			}

			uint256 _gen2TokenCount = _gen2TokenIds[i].ids.length;
			if (_gen2TokenCount != 0) {
				uint256 _count = bags[_bagId].gen2TokenIds.length;
				require(_count >= _gen2TokenCount, "too many to unstake");
				for (uint256 j = 0; j < _gen2TokenCount; j++) {
					require(gen2BagIds[_gen2TokenIds[i].ids[j]] == _bagId, "gen2 not found in the bag");
					for (uint256 k = 0; k < _count; k++){
						if (_gen2TokenIds[i].ids[j] == bags[_bagId].gen2TokenIds[k]) {
							gen2.safeTransferFrom(address(this), msg.sender, _gen2TokenIds[i].ids[j]);
							bags[_bagId].gen2TokenIds[k] = bags[_bagId].gen2TokenIds[_count-1];
							bags[_bagId].gen2Rarities[k] = bags[_bagId].gen2Rarities[_count-1];
							bags[_bagId].gen2TokenIds.pop();
							bags[_bagId].gen2Rarities.pop();
							_count--;
							delete gen2BagIds[_gen2TokenIds[i].ids[j]];
						}
					}  
				}

				if (!_isValidGenesisId(bags[_bagId].genTokenId) && _count == 0) {
					delete bags[_bagId];
					_burn(_bagId);
					break;
				}
				bags[_bagId].lastStateChange = block.timestamp;
			}
		}                        
	}

	function claim() external nonReentrant {
		uint256 _totalBags = balanceOf(msg.sender);
		uint256 _totalAmount = 0;
		uint256 _now = block.timestamp;
			
		for (uint256 i = 0; i < _totalBags; i++){
			uint256 bagId = tokenByIndex(i);
			uint256 _unclaimed = _calculateStakeReward(bagId);
			bags[bagId].unclaimedBalance += _unclaimed;
			if (bags[bagId].unclaimedBalance != 0){
				_totalAmount += bags[bagId].unclaimedBalance;
				emit Claimed(msg.sender, bagId, bags[bagId].unclaimedBalance);
				bags[bagId].unclaimedBalance = 0;
				bags[bagId].lastStateChange = _now;
			}
		}
		require(_totalAmount != 0, "nothing to claim");
		rewardsToken.mint(msg.sender, _totalAmount);
	}

	function _calculateStakeReward(uint256 _bagId) internal view returns (uint256) {
		uint256 total = 0;
		// uint256 period = ((block.timestamp - bags[_bagId].lastStateChange) / 1 days);
		uint256 period = ((block.timestamp - bags[_bagId].lastStateChange) / 10 minutes);
		uint256 baseEarning = 0;
		uint256 gen2TokenLen = bags[_bagId].gen2TokenIds.length;
		uint256 genesisRateMultiplier = 1;
		
		if(bags[_bagId].genRarity != 0) {
			genesisRateMultiplier = genMultipliers[bags[_bagId].genRarity];
		}

		for(uint256 i = 0; i < bags[_bagId].gen2Rarities.length; i++ ) {
			baseEarning += gen2Earnings[bags[_bagId].gen2Rarities[i]];
		}

		if(gen2TokenLen <= 1) {
			total = baseEarning * genesisRateMultiplier * period;
		}
		else if(gen2TokenLen == 2) {
			total = (baseEarning * genesisRateMultiplier * period) * 21 / 20;
		}
		else if(gen2TokenLen == 3) {
			total = (baseEarning * genesisRateMultiplier * period) * 23 / 20;
		} 

    return total;
  }

	function _isValidGenesisId(uint256 id) internal pure returns(bool) {
		if (id > 0 && id < 334) {
			return true;
		}
		else {
			return false;
		}
	}

	function _isValidGen2Id(uint256 id) internal pure returns(bool) {
		if (id < 3333) {
			return true;
		}
		else {
			return false;
		}
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