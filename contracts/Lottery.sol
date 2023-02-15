// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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

contract Lottery is VRFConsumerBaseV2, Ownable, KeeperCompatibleInterface {
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
	uint32 private constant NUM_WORDS = 1;
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

	// Will hold current lottery treasury (all NFTs in lottery pot)
	nft[] public s_tresury;
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

	/* --- Functions --- */
	constructor(
		address _priceFeedAddress,
		address _vrfCoordinatorV2,
		bytes32 _gasLane,
		uint64 _subscriptionId,
		uint32 _callbackGasLimit,
		uint256 _interval
	) VRFConsumerBaseV2(_vrfCoordinatorV2) {
		i_initialNFTValue = 20 * (10**18); // 18 decimals for our starting nft value which is 20 usd
		ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress); // get eth to usd price feed instance
		i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorV2); // get vrfcoordinator instance
		s_lotteryState = LOTTERY_STATE.CLOSED;
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
		returns (
			bool upKeepNeeded,
			bytes memory /*performData*/
		)
	{
		bool isOpen = (s_lotteryState == LOTTERY_STATE.OPEN);
		bool timePassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
		bool hasPlayers = (s_players.length > 0);
		bool hasBalance = (s_tresury.length > 0); // Check for at least one NFT in Lottery treasury
		upKeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
		return (upKeepNeeded, "0x");
	}

	/**
	 * dev: This the function that will perform the upkeep based upon interval and is acting as endLottery function
	 */
	function performUpkeep(
		bytes calldata /* performData */
	) external override {
		(bool upKeepNeeded, ) = checkUpkeep(new bytes(0));
		if (!upKeepNeeded) {
			// error with information to understand why up keep is not required
			revert Lottery__UpKeepNotNeeded(
				s_tresury.length,
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

	function enterLottery(address _collectionAddress, uint256 _tokenId)
		public
		payable
	{
		require(
			s_lotteryState == LOTTERY_STATE.OPEN,
			"Can't join now, Lottery Closed!"
		);
		// require(
		// 	token._isApprovedOrOwner(_msgSender(), _tokenId),
		// 	"ERC721: transfer caller is not owner nor approved"
		// );
		token = IERC721(_collectionAddress);
		// 1st added NFT to lottery treasury
		if (s_tresury.length <= 0) {
			if (
				getNFTValue(nft(_collectionAddress, _tokenId, msg.sender)) >=
				i_initialNFTValue
			) {
				revert Lottery__NftValueTooLow();
			}
		}
		// Not 1st added NFT to lottery treasury
		else {
			require(
				inBetween(
					getNFTValue(nft(_collectionAddress, _tokenId, msg.sender)),
					85 % getTreasuryAvg(),
					115 % getTreasuryAvg()
				),
				"You need to add an NFT with 15% margin range of current lottery treasury avarage"
			); //To implement getNFTValue & getTreasuryAvg
		}
		token.transferFrom(msg.sender, address(this), _tokenId);
		s_tresury.push(nft(_collectionAddress, _tokenId, msg.sender)); //push to NFT Treasury array
		s_players.push(payable(msg.sender)); // push current player to our players array
		emit LotteryEnter(msg.sender, _collectionAddress, _tokenId);
	}

	function inBetween(
		uint256 value,
		uint256 min,
		uint256 max
	) internal view returns (bool) {
		require(min < max);
		return value >= min && value <= max;
	}

	// Client will send token value using Moralis api and set NFT value
	function setNFTValue(
		address _collectionAddress,
		uint256 _tokenId,
		uint256 _value
	) public onlyOwner {}

	function startLottery() public onlyOwner {
		if (s_lotteryState == LOTTERY_STATE.CLOSED) {
			revert Lottery__CantJoinClosed();
		}
		s_lotteryState = LOTTERY_STATE.OPEN;
	}

	function fulfillRandomWords(
		uint256, /*_requestId*/
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
		(bool success, ) = s_recentWinner.call{ value: address(this).balance }(
			""
		); // transfer the latest winner with the lottery balance
		if (!success) {
			revert Lottery__transferTreasuryFailed();
		}

		// reset lottery stats
		s_players = new address payable[](0); // reset players array size 0
		s_tresury = new nft[](0);
		s_lastTimeStamp = block.timestamp; //reset last time stamp
	}

	/* --- View / Pure Functions --- */
	function getTreasuryAvg() public view returns (uint256) {
		uint256 avg = 0;
		for (
			uint256 nftTreasuryIndex = 0;
			nftTreasuryIndex <= s_tresury.length;
			nftTreasuryIndex++
		) {
			avg += getNFTValue(s_tresury[nftTreasuryIndex]);
		}
		return avg;
	}

	function getPlayer(uint256 index) public view returns (address) {
		return s_players[index];
	}

	function getRecenetWinner() public view returns (address) {
		return s_recentWinner;
	}

	// Returns value in USD of an NFT
	function getNFTValue(nft memory _nft) public view returns (uint256) {
		return 1;
	}

	function getLotteryTreasury() public view returns (uint256) {
		uint256 balance = address(this).balance;
		return balance;
	}

	function getNumOfParticipants() public view returns (uint256) {
		return s_players.length;
	}

	function getEntranceFee() public view returns (uint256) {
		(, int256 price, , , ) = ethUsdPriceFeed.latestRoundData(); // fetching current eth usd price 8 decimals
		uint256 adjustedPrice = uint256(price) * 10**10; // now price will be represented in 18 decimals as well
		uint256 costToEnter = (i_initialNFTValue * 10**18) / adjustedPrice; // math to get our result in 18 decimals as well
		return costToEnter;
	}

	function getLotteryState() public returns (LOTTERY_STATE) {
		return s_lotteryState;
	}
}
