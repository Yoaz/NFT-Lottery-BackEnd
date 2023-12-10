// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

/** @title A Simple NFT Lottery Contract
 * @author Yoaz Shmider
 * @notice This contract implements Chainlink's V3Aggregator
  and VRF Consumer Base V2
 * @dev There are few features that needs to be fixed
 */

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

error Lottery__NftValueTooLow();
error Lottery__transferTreasuryFailed();
error Lottery__CantJoinClosed();
error Lottery__UpKeepNotNeeded(
	uint256 treasuryBalance,
	uint256 playersLength,
	uint256 lotteryState
);
error Lottery__NFTValueNotMatch();

contract Lottery is
	VRFConsumerBaseV2,
	Ownable,
	KeeperCompatibleInterface,
	IERC721Receiver,
	ERC165Storage
{
	/* --- Types --- */
	enum LOTTERY_STATE {
		OPEN,
		CLOSED,
		CALCULATING_WINNER
	}

	// Will hold item information (collection addresss + token id)
	struct nft {
		address _tokenAddress;
		uint256 _tokenId;
		address _owner;
	}

	/* --- State Varaibels --- */

	// Chainlink VRF Varibles
	bytes32 private immutable i_gasLane;
	uint64 private immutable i_subscriptionId;
	uint16 private constant REQUEST_CONFIRMATIONS = 3;
	uint32 private immutable i_callbackGasLimit;
	uint32 private constant NUM_WORDS = 2; // Retrieve 2 randoms numbers in one call.
	VRFCoordinatorV2Interface private immutable i_vrfCoordinator;

	// Lottery Variables
	IERC721 internal token;
	address payable[] private s_players; // To keep track of the participants
	uint256 private immutable i_initialNFTValue;
	AggregatorV3Interface internal ethUsdPriceFeed;
	address payable private s_recentWinner;
	LOTTERY_STATE private s_lotteryState;
	uint256 private s_lastTimeStamp;
	uint256 private immutable i_interval;
	nft s_tempToken; // This will be to hold NFT token to evulate rather for evulations of requirements.

	// Will hold current lottery session treasury (all NFTs in lottery pot)
	nft[] public s_sessionTreasury;
	// Will hold lottery self/dao treasury
	//(every round/session one NFT randomly assign to the smart contract)
	nft[] public s_daoTreasury;
	// To keep track of nft's array index to actual NFT item
	mapping(bytes32 => nft) private indexToNFT;

	/* --- Events --- */
	event LotteryEnter(
		address indexed player,
		address indexed collectionAddress,
		uint256 indexed tokenId
	);
	event requestedLotteryWinner(uint256 requestId);
	event winnerPicked(address indexed winner);
	event tokenForSmartContractPicked(
		address indexed collectionAdress,
		uint256 indexed tokenId
	);

	/* --- Functions --- */
	constructor(
		address _priceFeedAddress,
		address _vrfCoordinatorV2,
		bytes32 _gasLane,
		uint64 _subscriptionId,
		uint32 _callbackGasLimit,
		uint256 _interval
	) VRFConsumerBaseV2(_vrfCoordinatorV2) {
		_registerInterface(IERC721Receiver.onERC721Received.selector); //Requirement for been able to recieve ERC721 (NFT) tokens to a smart contract using safeTransfer
		i_initialNFTValue = 20 * (10 ** 18); // 18 decimals for our starting nft value which is 20 usd
		ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress); // get eth to usd price feed instance
		i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorV2); // get vrfcoordinator instance
		s_lotteryState = LOTTERY_STATE.OPEN;
		i_gasLane = _gasLane;
		i_subscriptionId = _subscriptionId;
		i_callbackGasLimit = _callbackGasLimit;
		s_lastTimeStamp = block.timestamp; // Initiate last block time stamp to the current one when deploying contract
		i_interval = _interval; // Initate interval based on deplyoing interval logic
	}

	/**
	 * dev: This is the function that the chainlink keeper will look to return true to update state
	 * The following should be true in order to return true:
	 * 1. The time Interval should have passed
	 * 2. The Lottery should have at least one NFT added to treasury and 1 player
	 * 3. The Chainlink subscription is funded with Link Token
	 */
	function checkUpkeep(
		bytes memory /*checkData*/
	)
		public
		view
		override
		returns (bool upKeepNeeded, bytes memory /*performData*/)
	{
		bool isOpen = (s_lotteryState == LOTTERY_STATE.OPEN);
		bool timePassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
		bool hasPlayers = (s_players.length > 0);
		bool hasBalance = (s_sessionTreasury.length > 0); // Check for at least one NFT in Lottery treasury
		upKeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
		return (upKeepNeeded, "0x");
	}

	/**
	 * dev: This the function that will perform the upkeep based upon interval and is acting as endLottery function
	 */
	function performUpkeep(bytes calldata /* performData */) external override {
		(bool upKeepNeeded, ) = checkUpkeep(new bytes(0));
		if (!upKeepNeeded) {
			// error with information to understand why up keep is not required
			revert Lottery__UpKeepNotNeeded(
				s_sessionTreasury.length,
				s_players.length,
				uint256(s_lotteryState)
			);
		}

		uint256 requestId = i_vrfCoordinator.requestRandomWords(
			i_gasLane,
			i_subscriptionId,
			REQUEST_CONFIRMATIONS,
			i_callbackGasLimit,
			NUM_WORDS
		);

		emit requestedLotteryWinner(requestId);
	}

	function enterLottery(
		address _collectionAddress,
		uint256 _tokenId
	) external payable {
		if (s_lotteryState == LOTTERY_STATE.CLOSED) {
			revert Lottery__CantJoinClosed();
		}
		// require(
		// 	token._isApprovedOrOwner(_msgSender(), _tokenId),
		// 	"ERC721: transfer caller is not owner nor approved"
		// );
		token = IERC721(_collectionAddress);
		// Assign storage tempToken var with current stats
		s_tempToken._tokenAddress = _collectionAddress;
		s_tempToken._tokenId = _tokenId;
		s_tempToken._owner = msg.sender;

		/* 
		*** To implment the whole NFT value algorithm *** 

		// 1st added NFT to lottery treasury
		if (s_sessionTreasury.length <= 0) {
			if (getNFTValue() >= i_initialNFTValue) {
				revert Lottery__NftValueTooLow();
			}
		}
		// Not 1st added NFT to lottery treasury
		else {
			// NFT Value should be in lottery pot range (15% margin up or down)
			if (
				!inBetween(
					getNFTValue(),
					85 % getTreasuryAvg(),
					115 % getTreasuryAvg()
				)
			) {
				revert Lottery__NFTValueNotMatch();
			} //To implement getNFTValue & getTreasuryAvg
		}

		*/

		token.safeTransferFrom(msg.sender, address(this), _tokenId);
		s_sessionTreasury.push(s_tempToken); //push to NFT Treasury array
		s_players.push(payable(msg.sender)); // push current player to our players array
		emit LotteryEnter(msg.sender, _collectionAddress, _tokenId);
	}

	function inBetween(
		uint256 value,
		uint256 min,
		uint256 max
	) internal pure returns (bool) {
		require(min < max);
		return value >= min && value <= max;
	}

	// Client will send token value using Moralis api and set NFT value
	function setNFTValue(
		address _collectionAddress,
		uint256 _tokenId,
		uint256 _value
	) public onlyOwner {}

	function fulfillRandomWords(
		uint256 /*_requestId*/,
		uint256[] memory _randomWords
	) internal override {
		require(
			s_lotteryState == LOTTERY_STATE.CALCULATING_WINNER,
			"Not there yet!!"
		);
		require(_randomWords.length > 0, "Random not found!");
		uint256 indexOfWinner = _randomWords[0] % s_players.length;
		s_recentWinner = s_players[indexOfWinner];
		s_lotteryState = LOTTERY_STATE.OPEN;
		emit winnerPicked(s_recentWinner);
		// Receiving one token to the smartcontract
		uint256 daoTokenIndex = _randomWords[1] % s_sessionTreasury.length;
		emit tokenForSmartContractPicked(
			s_sessionTreasury[daoTokenIndex]._tokenAddress,
			s_sessionTreasury[daoTokenIndex]._tokenId
		);
		// transfer the latest winner with the lottery balance + random chosen index for
		// smartcontract nft will be sent to the s_daoTreasury
		bool success = tokenDistributor(s_recentWinner, daoTokenIndex);
		if (!success) {
			revert Lottery__transferTreasuryFailed();
		}

		// reset lottery stats
		s_players = new address payable[](0); // reset players array size 0
		// s_sessionTreasury = new nft[](0);
		s_lastTimeStamp = block.timestamp; //reset last time stamp
	}

	/**
	 * dev: This function is a requirement for a smart contract that recieves an ERC721
	 * tokens. As an IERC721Receiver, safeTransfer will check for the recieving smart contract
	 * that has does this function implemented so NFT will not be stuck in this smart contract forever
	 */
	function transfer(
		address to,
		address collection_address,
		uint256 tokenId
	) public {
		// Change back to internal onlyOwner after create local testing appropiate
		IERC721(collection_address).safeTransferFrom(
			address(this),
			to,
			tokenId
		);
	}

	/**
	 * dev: This will take care of transfering all NFT's from treasury to wallet address besides the daoTokenIndex
	 * that will transfer that token to the smart contract daoTreasury
	 * internal onlyOwner function that would be called by fulfilRondomness after winner seccfully picked
	 */
	function tokenDistributor(
		address _wallet,
		uint256 daoTokenIndex
	) internal returns (bool) {
		for (
			uint256 tokenIndex = 0;
			tokenIndex < s_sessionTreasury.length - 1;
			tokenIndex++
		) {
			// if current array index equal to daoToken random index
			// Then move current nft to smartcontract (this) daoTresury
			if (tokenIndex == daoTokenIndex) {
				s_daoTreasury.push(s_sessionTreasury[tokenIndex]);
			} else {
				transfer(
					_wallet,
					s_sessionTreasury[tokenIndex]._tokenAddress,
					s_sessionTreasury[tokenIndex]._tokenId
				);
			}
		}
		return true;
	}

	/**
	 * dev: This function is a requirement for a smart contract that recieves an ERC721
	 * tokens. As an IERC721Receiver, this function will be called by the ERC721 holder contract
	 * upon transfering the token.
	 */
	function onERC721Received(
		address operator,
		address from,
		uint256 tokenId,
		bytes calldata data
	) public override returns (bytes4) {
		return this.onERC721Received.selector;
	}

	/* --- View / Pure Functions --- */
	function getTreasuryAvg() public returns (uint256) {
		uint256 avg = 0;
		for (
			uint256 nftTreasuryIndex = 0;
			nftTreasuryIndex <= s_sessionTreasury.length;
			nftTreasuryIndex++
		) {
			s_tempToken = s_sessionTreasury[nftTreasuryIndex];
			avg += getNFTValue();
		}
		return avg;
	}

	function getPlayer(uint256 index) public view returns (address) {
		return s_players[index];
	}

	function getRecentWinner() public view returns (address) {
		return s_recentWinner;
	}

	// Returns value in USD of an NFT
	function getNFTValue() public pure returns (uint256) {
		return 1;
	}

	function getNumOfParticipants() public view returns (uint256) {
		return s_players.length;
	}

	function getEntranceFee() public view returns (uint256) {
		(, int256 price, , , ) = ethUsdPriceFeed.latestRoundData(); // fetching current eth usd price 8 decimals
		uint256 adjustedPrice = uint256(price) * 10 ** 10; // now price will be represented in 18 decimals as well
		uint256 costToEnter = (i_initialNFTValue * 10 ** 18) / adjustedPrice; // math to get our result in 18 decimals as well
		return costToEnter;
	}

	function getLotteryState() public view returns (LOTTERY_STATE) {
		return s_lotteryState;
	}

	function getNumWords() public pure returns (uint256) {
		return NUM_WORDS;
	}

	function getRequestConfirmations() public pure returns (uint256) {
		return REQUEST_CONFIRMATIONS;
	}

	function getLatestTimeStamp() public view returns (uint256) {
		return s_lastTimeStamp;
	}

	function getInterval() public view returns (uint256) {
		return i_interval;
	}

	function getLotteryTreasury() public view returns (nft[] memory) {
		nft[] memory result = new nft[](s_sessionTreasury.length);
		result = s_sessionTreasury;
		return result;
	}
}
