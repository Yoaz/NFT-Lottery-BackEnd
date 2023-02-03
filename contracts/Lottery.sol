// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract Lottery is VRFConsumerBase, Ownable {
    address payable[] public players; // To keep track of the participants
    address[] public winners; // To keep track of winners history
    address payable public recentWinner;
    uint256 randomness;
    uint256 public usdEntryFee;
    AggregatorV3Interface internal ethUsdPriceFeed;
    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }
    event requestedRandomness(bytes32 requestId);
    LOTTERY_STATE public lottery_state;
    uint256 fee;
    bytes32 keyHash;

    constructor(
        address _priceFeedAddress,
        address _vrfCoordinator,
        address _link,
        uint256 _fee,
        bytes32 _keyHash
    ) public VRFConsumerBase(_vrfCoordinator, _link) {
        usdEntryFee = 20 * (10**18); // 18 decimals for our entrance fee which is 20 usd
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress); // get eth to usd price feed instance
        lottery_state = LOTTERY_STATE.CLOSED;
        fee = _fee;
        keyHash = _keyHash;
    }

    function enter() public payable {
        require(
            lottery_state == LOTTERY_STATE.OPEN,
            "Can't join now, Lottery Closed!"
        );
        require(msg.value >= getEntranceFee()); //
        players.push(msg.sender); // push current player to our players array
    }

    function getEntranceFee() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData(); // fetching current eth usd price 8 decimals
        uint256 adjustedPrice = uint256(price) * 10**10; // now price will be represented in 18 decimals as well
        uint256 costToEnter = (usdEntryFee * 10**18) / adjustedPrice; // math to get our result in 18 decimals as well
        return costToEnter;
    }

    function startLottery() public onlyOwner {
        require(
            lottery_state == LOTTERY_STATE.CLOSED,
            "Can't start Lottery yet!"
        );
        lottery_state = LOTTERY_STATE.OPEN;
    }

    function endLottery() public onlyOwner {
        lottery_state = LOTTERY_STATE.CALCULATING_WINNER;
        bytes32 requestId = requestRandomness(keyHash, fee);
        emit requestedRandomness(requestId); // Emiting the request id as blockchian event to use for local devlopement test
    }

    function fulfillRandomness(bytes32 _requestId, uint256 _randomness)
        internal
        override
    {
        require(
            lottery_state == LOTTERY_STATE.CALCULATING_WINNER,
            "Not there yet!!"
        );
        require(_randomness > 0, "Random not found!");
        uint256 indexOfWinner = _randomness % players.length;
        recentWinner = players[indexOfWinner];
        winners.push(recentWinner); // Insert latest winner to the winners recording
        recentWinner.transfer(address(this).balance); // transfer the latest winner with the lottery balance

        // reset lottery stats
        players = new address payable[](0);
        lottery_state = LOTTERY_STATE.CLOSED;
        randomness = _randomness;
    }

    function getLotteryTreasury() public view returns(uint256){
        uint256 balance = address(this).balance;
        return balance;
    }

    function getNumOfParticipants() public view returns(uint256){
        return players.length;
    }
}
