//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IJiraToken.sol";
import "./Whitelist.sol";
import "hardhat/console.sol";

contract Staking is Initializable, WhitelistChecker, ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC721EnumerableUpgradeable, IERC721ReceiverUpgradeable {
	using CountersUpgradeable for CountersUpgradeable.Counter;
  CountersUpgradeable.Counter private ticketIds;

	IERC721Upgradeable public genesis;
	IERC721Upgradeable public gen2;
	IJiraToken public rewardsToken;

	struct StakeInfo {
		uint256 genesisTokenId;
		uint256 genesisMultiplier;
		uint256[3] gen2tokenIds;
		uint256[3] gen2Rates;
		uint256 since;
	}

	address designatedSigner; //TODO : Set Address

	/// @dev ticketId -> Stake info
  mapping(uint256 => StakeInfo) public stakeInfos;

	mapping(address => uint256) private _balances;
	mapping(address => uint256) public claims;
	mapping(uint256 => uint256) public genesisMultipliers;
	mapping(uint256 => uint256) public gen2Rates;


	event Staked(address indexed user, uint256 ticketId);
	event UnStaked(address indexed user, uint256 ticketId, uint256 reward);
	event Claimed(address indexed user, uint256 ticketId, uint256 reward);
	event ClaimedAll(address indexed user, uint256 reward);

	function initialize(address _genesis, address _gen2, address _rewardsToken) initializer public {
		__Whitelist_init();
		__ERC721_init("GenStaking", "GS");
		__Ownable_init();

		genesis = IERC721Upgradeable(_genesis);
		gen2= IERC721Upgradeable(_gen2);
    rewardsToken = IJiraToken(_rewardsToken);

		genesisMultipliers[1] = 3; // Legendary
		genesisMultipliers[2] = 2; // Common

		gen2Rates[1] = 4; // Common
		gen2Rates[2] = 6; // Rare
		gen2Rates[3] = 8; // Legendary
	}

	function stake(whitelisted memory whitelist) external nonReentrant {
		console.log(designatedSigner);
		require(getSigner(whitelist) == designatedSigner,"Invalid signature");
    require(msg.sender == whitelist.whiteListAddress,"not same user");

		if(whitelist.genTokenId != 0) {
			require(msg.sender == genesis.ownerOf(whitelist.genTokenId), "Not genesis owner");
			genesis.safeTransferFrom(msg.sender, address(this), whitelist.genTokenId);
		}

		for (uint256 i = 0; i < whitelist.gen2TokenIds.length; i++) {
			uint256 gen2TokenId = whitelist.gen2TokenIds[i];
			require(gen2TokenId != 0, "invalid gen2 tokenId");
			require(msg.sender == gen2.ownerOf(gen2TokenId), "Not gen2 owner");
			gen2.safeTransferFrom(msg.sender, address(this), gen2TokenId);
		}

		ticketIds.increment();
		uint256 ticketId = ticketIds.current();
		_safeMint(msg.sender, ticketId);

		stakeInfos[ticketId] = StakeInfo({
			genesisTokenId: whitelist.genTokenId,
			gen2tokenIds: whitelist.gen2TokenIds,
			genesisMultiplier: whitelist.genMultiplier,
			gen2Rates: whitelist.gen2Rates,
			since: block.timestamp
		});
		
		emit Staked(msg.sender,	ticketId);
	}

	function unStake(uint256[] memory _ticketIds) external nonReentrant {
		uint256[] memory genesisTokenIds = new uint256[](_ticketIds.length);
		for (uint256 i = 0; i < _ticketIds.length; i++) {
			uint256 ticketId = _ticketIds[i];
			require(msg.sender == ownerOf(ticketId), "Not ticket owner");
			uint256 _genesisTokenId = stakeInfos[ticketId].genesisTokenId;
			genesisTokenIds[i] = _genesisTokenId;
			genesis.safeTransferFrom(address(this), msg.sender, _genesisTokenId);
			
			uint256 getReward = getStakeReward();
			if(getReward > 0) {
				rewardsToken.mint(msg.sender, getReward);
			}
			delete stakeInfos[ticketId];
			delete claims[msg.sender];
			emit UnStaked(msg.sender, ticketId, getReward);
		}
	}

	function claim(uint256 _ticketId, uint256 _amount) external nonReentrant {
		require(msg.sender == ownerOf(_ticketId), "Not owner");
		uint256  stakeReward = _calculateStakeReward(_ticketId) - claims[msg.sender];
		require(_amount != 0, "Invalid amount");
		require(stakeInfos[_ticketId].gen2tokenIds.length != 0, "No stake");
		require(stakeReward >= _amount, "Cannot claim more than you own");
		claims[msg.sender] += _amount;
		rewardsToken.mint(msg.sender, _amount);
		emit Claimed(msg.sender, _ticketId, _amount);
	}

	function claimAll() external nonReentrant {
		uint256 _amount = getStakeReward();
		require(_amount != 0, "Invalid amount");
		rewardsToken.mint(msg.sender, _amount);
		claims[msg.sender] += _amount;
		emit ClaimedAll(msg.sender, _amount);
	}

	function _calculateStakeReward(uint256 _ticketNumber) internal view returns (uint256) {
		uint256 period = ((block.timestamp - stakeInfos[_ticketNumber].since) / 1 days);
		uint256 baseEarning = 0;
		uint256 gen2RateMultiplier = 1;
		uint256 genesisRateMultiplier = 1;

		if(stakeInfos[_ticketNumber].genesisMultiplier != 0) {
			genesisRateMultiplier = genesisMultipliers[stakeInfos[_ticketNumber].genesisMultiplier];
		}

		if(stakeInfos[_ticketNumber].gen2tokenIds.length == 2) {
			gen2RateMultiplier = uint256(21) / uint256(20);
		}
		else if(stakeInfos[_ticketNumber].gen2tokenIds.length == 3) {
			gen2RateMultiplier = uint256(23) / uint256(20);
		}

		for(uint256 i = 0; i < stakeInfos[_ticketNumber].gen2Rates.length; i++ ) {
			baseEarning += gen2Rates[stakeInfos[_ticketNumber].gen2Rates[i]];
		}

    return baseEarning * gen2RateMultiplier * genesisRateMultiplier * period;
  }

	function getStakeReward() public view returns (uint256) {
		uint256 ticketCounts = balanceOf(msg.sender);
		uint256 totalReward = 0;
		for(uint256 i = 0; i < ticketCounts; i++ ) {
			uint256 ticketNumber = tokenByIndex(i);
			if(stakeInfos[ticketNumber].since > 0) {
				totalReward += _calculateStakeReward(ticketNumber) - claims[msg.sender];
			}
		}

		return totalReward;
  }

	function modifySigner(address _signer) external onlyOwner {
		designatedSigner = _signer;
	}

	function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
		return this.onERC721Received.selector;
	}
}