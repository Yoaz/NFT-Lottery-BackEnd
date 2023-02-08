// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Lottery is VRFConsumerBase, Ownable {
    address payable[] public players; // To keep track of the participants
    address[] public winners; // To keep track of winners history
    address payable public recentWinner;
    uint256 randomness;
    uint256 public initialNFTValue;
    AggregatorV3Interface internal ethUsdPriceFeed;
    IERC721 internal token;
    
    // Will hold item information (collection addresss + token id)
    struct nft
    {
        address _tokenAddress;
        uint256 _tokenId;
        address _owner;
    };
    // Will hold current lottery treasury (all NFTs in lottery pot)
    nft[] public treasury;
    // To keep track of nft array index to actual NFT item
    mapping(bytes32 => nft) private indexToNFT;

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
        initialNFTValue = 20 * (10**18); // 18 decimals for our starting nft value which is 20 usd
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress); // get eth to usd price feed instance
        lottery_state = LOTTERY_STATE.CLOSED;
        fee = _fee;
        keyHash = _keyHash;
    }

    function enter(address _collectionAddress, uint256 _tokenId) public payable {
        require(
            lottery_state == LOTTERY_STATE.OPEN,
            "Can't join now, Lottery Closed!"
        );
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        // 1st added NFT
        if(treasury.length <=0){
            require(getNFTValue(_collectionAddress, _tokenId) >= initialNFTValue, "1st lottery NFT needs to be at least 20USD worth!");
        }
        // Not 1st added NFT
        else{
            require(getNFTValue() >= 1.15 * getTreasuryAvg() || getNFTValue() <= 1.15 * getTreasuryAvg(), "You need to add an NFT with 15% margin range of current lottery treasury"); //To implement getNFTValue & getTreasuryAvg 
        }
        token.transferFrom(msg.sender, address(this), _tokenId);
        treasury.push(nft(_collectionAddress, _tokenId, msg.sender)); //push to NFT Treasury array
        players.push(msg.sender); // push current player to our players array
    }

    // Client will send token value using Moralis api and set NFT value
    function setNFTValue(address _collectionAddress, uint256 _tokenId, uint256 _value) public onlyOwner{

    }

    function startLottery() public onlyOwner 
    {
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


    /* Getter Functions */
    function getTreasuryAvg() public view returns(uint256){
        for(uint256 i= )
    }

    // Returns value in USD of an NFT 
    function getNFTValue(nft _nft) public view returns(uint256){
        return 1;
    }

    function getLotteryTreasury() public view returns(uint256){
        uint256 balance = address(this).balance;
        return balance;
    }

    function getNumOfParticipants() public view returns(uint256){
        return players.length;
    }

    function getEntranceFee() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData(); // fetching current eth usd price 8 decimals
        uint256 adjustedPrice = uint256(price) * 10**10; // now price will be represented in 18 decimals as well
        uint256 costToEnter = (initialNFTValue * 10**18) / adjustedPrice; // math to get our result in 18 decimals as well
        return costToEnter;
    }
}
