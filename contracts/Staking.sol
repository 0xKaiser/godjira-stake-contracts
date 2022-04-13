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
import "./Whitelist.sol";
import "hardhat/console.sol";


contract Staking is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, WhitelistChecker, ERC721EnumerableUpgradeable, IERC721ReceiverUpgradeable {

	using CountersUpgradeable for CountersUpgradeable.Counter;
	using ECDSAUpgradeable for bytes;
	CountersUpgradeable.Counter private bagIds;

	IERC721Upgradeable public genesis;
	IERC721Upgradeable public gen2;
	IJiraToken public rewardsToken;

	struct Bag {
		uint256 genTokenId;
		uint256[] gen2TokenIds;
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
	uint256 public time;

	/// @dev bagId -> Stake info
  	mapping(uint256 => Bag) public bags;

	/// @dev gen token id => bag id
  	mapping(uint256 => uint256) public genBagIds;
  
	/// @dev gen2 token id => bag id
	mapping(uint256 => uint256) public gen2BagIds;
	
	mapping(uint => uint) public genesisRarities;
	mapping(uint => uint) public gen2Rarities;
	mapping(uint => bool) public genIsInitialised;
	mapping(uint => bool) public gen2IsInitialised;

	uint256 public doubleRewardNumerator;
	uint256 public doubleRewardDenominator;
	uint256 public tripleRewardNumerator;
	uint256 public tripleRewardDenominator;
	
	mapping(uint256 => uint256) public genMultipliers;
	mapping(uint256 => uint256) public gen2Earnings;

	string public baseURI;
	string private newName;
	string private newSymbol;

	event Staked(address indexed user, uint256 bagId);
	event UnStaked(address indexed user, uint256 bagId, uint256 reward);
	event Claimed(address indexed user, uint256 bagId, uint256 reward);
	event AddBagInfo(address indexed user, uint256 bagId);

	function initialize(address _genesis, address _gen2, address _rewardsToken) initializer public {
		__ERC721_init("Godjira Staking Contact", "GS");
		__Ownable_init();

		genesis = IERC721Upgradeable(_genesis);
		gen2 = IERC721Upgradeable(_gen2);
    		rewardsToken = IJiraToken(_rewardsToken);

		genMultipliers[1] = 2; // Common
		genMultipliers[2] = 3; // Legendary

		gen2Earnings[1] = 4; // Common
		gen2Earnings[2] = 6; // Rare
		gen2Earnings[3] = 8; // Legendary

		doubleRewardNumerator = 21;
		doubleRewardDenominator = 20;
		tripleRewardNumerator = 23;
		tripleRewardDenominator = 20;

		time = 24 * 60 * 60;
	}

	function stake(
		Bag[] memory _bags,
		uint256[] memory _bagIds
	) external nonReentrant {
		uint256 totalBags = _bagIds.length;
		require(totalBags == _bags.length);

		for (uint256 i = 0; i < _bags.length; i++) {
			if (_bagIds[i] == 0) {
				_addNewBag(_bags[i].genTokenId, _bags[i].gen2TokenIds );
			}
			else {
				_addToBag(_bagIds[i], _bags[i].genTokenId, _bags[i].gen2TokenIds);
			}
		}
	}

	function _addNewBag(
		uint256 _genTokenId,
		uint256[] memory _gen2TokenIds
	) internal {
		uint256 _gen2TokenCount = _gen2TokenIds.length;
		require(_gen2TokenIds.length <= 3, "can't add more than 3");
		require(_isValidGenesisId(_genTokenId) || _gen2TokenCount > 0, "nothing to add");			
		
		bagIds.increment();
		uint256 bagId = bagIds.current();
				
		if(_isValidGenesisId(_genTokenId)) {
			require(msg.sender == genesis.ownerOf(_genTokenId), "not owner of genesis");
			require(genBagIds[_genTokenId] == 0, "genesis already staked");
			require(genIsInitialised[_genTokenId], "genesis not initialised");
		
			genBagIds[_genTokenId] = bagId;
			genesis.safeTransferFrom(msg.sender, address(this), _genTokenId);
		}
		
		if (_gen2TokenCount > 0){
			for (uint256 i = 0; i < _gen2TokenCount; i++) {
				require(msg.sender == gen2.ownerOf(_gen2TokenIds[i]), "not owner of gen2");
				require(gen2BagIds[_gen2TokenIds[i]] == 0, "gen2 already staked");
				require(gen2IsInitialised[_gen2TokenIds[i]], "gen2 not initialised");

				gen2BagIds[_gen2TokenIds[i]] = bagId;
				gen2.safeTransferFrom(msg.sender, address(this), _gen2TokenIds[i]);
			}
		}
		
		uint256 _now = block.timestamp;
		bags[bagId] = Bag({
			genTokenId: _genTokenId,
			gen2TokenIds: _gen2TokenIds,
			unclaimedBalance: 0,
			lastStateChange: _now
		});
		
		_safeMint(msg.sender, bagId);
		emit Staked(msg.sender, bagId);                  
	}

	function _addToBag(
		uint256 _bagId,
		uint256 _genTokenId,
		uint256[] memory _gen2TokenIds
	) internal {
		
		require(msg.sender == ownerOf(_bagId), "not bag owner");

		uint256 currentGen2Count = bags[_bagId].gen2TokenIds.length;
		uint256 _gen2Count = _gen2TokenIds.length;
		
		require(_isValidGenesisId(_genTokenId) || _gen2Count != 0, "nothing to add");
		require((currentGen2Count + _gen2Count) <= 3, "can't add more than 3 gen2s");
		
		uint256 _unclaimed = _calculateStakeReward(_bagId);
		bags[_bagId].unclaimedBalance += _unclaimed;
		
		if (_isValidGenesisId(_genTokenId)) {
			require(genBagIds[_genTokenId] == 0, "genesis already staked");
			require(_isValidGenesisId(bags[_bagId].genTokenId) != true, "genesis already present");
			require(msg.sender == genesis.ownerOf(_genTokenId), "not genesis owner");
			require(genIsInitialised[_genTokenId], "not initialised");
			
			bags[_bagId].genTokenId = _genTokenId;
			genBagIds[_genTokenId] = _bagId;
			genesis.safeTransferFrom(msg.sender, address(this), _genTokenId);
		}
		
		if (_gen2Count > 0){		
			for (uint256 i = 0; i < _gen2Count; i++) {
				require(_isValidGen2Id(_gen2TokenIds[i]), "invalid gen2 token");
				require(gen2BagIds[_gen2TokenIds[i]] == 0, "gen2 already staked");
				require(msg.sender == gen2.ownerOf(_gen2TokenIds[i]), "not gen2 owner");
				require(gen2IsInitialised[_gen2TokenIds[i]], "not initialised");
			
				bags[_bagId].gen2TokenIds.push(_gen2TokenIds[i]);
				gen2BagIds[_gen2TokenIds[i]] = _bagId;
				gen2.safeTransferFrom(msg.sender, address(this), _gen2TokenIds[i]);
			}
		}
				
		bags[_bagId].lastStateChange = block.timestamp;
		emit AddBagInfo(msg.sender, _bagId);
	}


	function unstake(
		uint256[] memory _bagIds,
		genTokenId[] memory _genTokenIds,
		gen2TokenId[] memory _gen2TokenIds
	) external {
		uint256 totalBags = _bagIds.length;
		require(totalBags == _genTokenIds.length);
		require(totalBags == _gen2TokenIds.length);

		for (uint256 i = 0; i < totalBags; i++) {
			uint256 _bagId = _bagIds[i];
			require(msg.sender == ownerOf(_bagId), "not bag owner");
			require(_isValidGenesisId(_genTokenIds[i].id) || _gen2TokenIds[i].ids.length != 0, "nothing to unstake");

			uint256 _unclaimed = _calculateStakeReward(_bagId);
			bags[_bagId].unclaimedBalance += _unclaimed;

			if (_isValidGenesisId(_genTokenIds[i].id)) {
				require(genBagIds[_genTokenIds[i].id] == _bagId, "genesis not in bag");
				
				bags[_bagIds[i]].genTokenId = 0;
				delete genBagIds[_genTokenIds[i].id];
				genesis.safeTransferFrom(address(this), msg.sender, _genTokenIds[i].id);
			}

			uint256 _gen2TokenCount = _gen2TokenIds[i].ids.length;
			if (_gen2TokenCount != 0) {
				uint256 _count = bags[_bagId].gen2TokenIds.length;
				require(_count >= _gen2TokenCount, "too many to unstake");
				for (uint256 j = 0; j < _gen2TokenCount; j++) {
					require(gen2BagIds[_gen2TokenIds[i].ids[j]] == _bagId, "gen2 not found in the bag");
					for (uint256 k = 0; k < _count; k++){
						if (_gen2TokenIds[i].ids[j] == bags[_bagId].gen2TokenIds[k]) {
							bags[_bagId].gen2TokenIds[k] = bags[_bagId].gen2TokenIds[_count-1];
							bags[_bagId].gen2TokenIds.pop();
							_count--;
							delete gen2BagIds[_gen2TokenIds[i].ids[j]];
							gen2.safeTransferFrom(address(this), msg.sender, _gen2TokenIds[i].ids[j]);
						}
					}  
				}
			}

			if (bags[_bagId].genTokenId == 0 && bags[_bagId].gen2TokenIds.length == 0) {
				if (bags[_bagId].unclaimedBalance > 0){
					rewardsToken.mint(msg.sender, bags[_bagId].unclaimedBalance);
				}
				delete bags[_bagId];
				_burn(_bagId);
			}
			else {
			bags[_bagId].lastStateChange = block.timestamp;
			}
		}                        
	}

	function claim() external nonReentrant {
		uint256 _totalBags = balanceOf(msg.sender);
		uint256 _totalAmount = 0;
		uint256 _now = block.timestamp;
			
		for (uint256 i = 0; i < _totalBags; i++){
			uint256 bagId = tokenOfOwnerByIndex(msg.sender, i);
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
		
		uint256 period = ((block.timestamp - bags[_bagId].lastStateChange) / time);
		uint256 gen2TokenLen = bags[_bagId].gen2TokenIds.length;
		
		if (period == 0 || gen2TokenLen == 0){
			return 0;
		}

		uint256 total = 0;
		uint256 baseEarning = 0;
		uint256 genesisRateMultiplier = 1;
		
		if(genesisRarities[bags[_bagId].genTokenId]>0) {
			genesisRateMultiplier = genMultipliers[genesisRarities[bags[_bagId].genTokenId]];
		}

		for(uint256 i = 0; i < bags[_bagId].gen2TokenIds.length; i++ ) {
			baseEarning += gen2Earnings[gen2Rarities[bags[_bagId].gen2TokenIds[i]]];
		}

		if(gen2TokenLen <= 1) {
			total = baseEarning * genesisRateMultiplier * period * 1 ether;
		}
		else if(gen2TokenLen == 2) {
			total = (baseEarning * genesisRateMultiplier * period) * (doubleRewardNumerator * 1 ether) / doubleRewardDenominator;
		}
		else if(gen2TokenLen == 3) {
			total = (baseEarning * genesisRateMultiplier * period) * (tripleRewardNumerator * 1 ether) / tripleRewardDenominator;
		} 

    		return total;
  	}

	function designatedSigner() external view onlyOwner returns (address) {
		return _designatedSigner;
	}

	function getGen2InBagByIndex (uint256 _bagId, uint256 _index) public view returns (uint256){
		uint256 tokenId = bags[_bagId].gen2TokenIds[_index];
		return tokenId;
	}

	function getTotalGen2InBag (uint256 bagId) public view returns (uint256){
		uint256 len = bags[bagId].gen2TokenIds.length;
		return len;
	}

	function getUnclaimedBalanceSinceLastChange (uint256 bagId) public view returns (uint256) {
		uint256 amount = _calculateStakeReward(bagId);
		return amount;
	}

	function _baseURI() internal view override returns (string memory) {
		return baseURI;
	}

	function setBaseURI(string memory _uri) public onlyOwner {
		baseURI = _uri;
	}

	function modifyName(string memory _name) public onlyOwner {
		newName = _name;
	}

	function modifySymbol(string memory _symbol) public onlyOwner {
		newSymbol = _symbol;
	}

	function name() public view virtual override returns (string memory) {
		return newName;
	}

	function symbol() public view virtual override returns (string memory) {
		return newSymbol;
	}

	function setGenesisRarity(whitelisted[] memory genesisInfo) external {
		for (uint256 i = 0; i < genesisInfo.length; i++){
			whitelisted memory data = genesisInfo[i];
			require (getSigner(data)==_designatedSigner,'!signer');
			require(data.isGenesis,"not allowed");
			genesisRarities[data.tokenId] = data.rarity;
			genIsInitialised[data.tokenId] = true;
		}
	}

	function setGen2Rarity(whitelisted[] memory gen2Info) external {
		for (uint256 i = 0; i < gen2Info.length; i++){
			whitelisted memory data = gen2Info[i];
			require (getSigner(data)==_designatedSigner,'!signer');
			require(!data.isGenesis,"not allowed");
			gen2Rarities[data.tokenId] = data.rarity;
			gen2IsInitialised[data.tokenId] = true;
		}
	}

	function editGen2BagIds(uint256 _bagId, uint256 _val) external onlyOwner {
		gen2BagIds[_bagId] = _val;
	}

	function editGenBagIds(uint256 _bagId, uint256 _val) external onlyOwner {
		genBagIds[_bagId] = _val;
	}

	function editGen2InBag(uint256 _bagId, uint256[] memory _val) external onlyOwner {
		bags[_bagId].gen2TokenIds = _val;
	}

	function modifyBagInfo(
		uint256 _bagId, 
		uint256 _genID, 
		uint256[] memory _gen2Ids,
		uint256 _unclaimedBalance,
		uint256 _lastStateChange
	) external onlyOwner {
		bags[_bagId].genTokenId = _genId;
		bags[_bagId].gen2TokenIds = _gen2TokenIds;
		bags[_bagId].unclaimedBalance = _unclaimedBalance;
		bags[_bagId].lastStateChange = _lastStateChange;
	} 

	function modifyMultipleGen2Bonus(uint256[] memory _vals) external onlyOwner {
		doubleRewardNumerator = _vals[0];
		doubleRewardDenominator = _vals[1];
		tripleRewardNumerator = _vals[2];
		tripleRewardDenominator = _vals[3];
	}

	function modifyGenesisMultipliers(uint256[] memory _mults) external onlyOwner {
		genMultipliers[1] = _mults[0];
		genMultipliers[2] = _mults[1];
	}

	function modifyGen2Earnings(uint256[] memory _rates) external onlyOwner {
		gen2Earnings[1] = _rates[0];
		gen2Earnings[2] = _rates[1];
		gen2Earnings[3] = _rates[2];
	}

	function modifyTime(uint256 _time) external onlyOwner {
		time = _time;
	}

	function modifySigner(address _signer) external onlyOwner {
		_designatedSigner = _signer;
	}

	function modifyGenesis(address _genesis) external onlyOwner {
		genesis = IERC721Upgradeable(_genesis); 
	}

	function modifyGen2(address _gen2) external onlyOwner {
		gen2 = IERC721Upgradeable(_gen2);
	}

	function modifyRewards(address _rewardsToken) external onlyOwner {
		rewardsToken = IJiraToken(_rewardsToken);
	}
	
	function _isValidGenesisId(uint256 id) internal pure returns(bool) {
		bool isValid = ((id > 0 && id < 334) ? true : false);
		return isValid;
	}

	function _isValidGen2Id(uint256 id) internal pure returns(bool) {
		bool isValid = (id < 3333 ? true : false);
		return isValid;
	}

	function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
		return this.onERC721Received.selector;
	}
}
