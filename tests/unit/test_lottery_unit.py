from brownie import network, config, exceptions, chain
from scripts.helpful_scripts import get_account, LOCAL_BLOCKCHAIN_DEVELOPMENT, FORKED_LOCAL_ENVOIRMENT
import pytest
from scripts.deploy import deploy_lottery
import time

token_id = [0, 1]


def test_can_join_lottery():
    # Arrange
    # if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
    #     pytest.skip()
    account = get_account()
    (lottery, token) = deploy_lottery()
    collection_address = token.address
    # Act
    # Minting an NFT from ERC721 so we can try and enter with it to the lottery
    tx = token._safeMint(account.address, 0, {"from": account})
    tx.wait(1)
    print(f"Minted a new NFT from {collection_address} token id: {token_id[0]} to account address: {account.address}")
    tx = token.approve(lottery.address, token_id[0], {"from": account})
    tx.wait(1)
    print(f"Approved to spend {collection_address} - {token_id[0]} to contract: {token.getApproved(token_id[0])}!")
    tx = lottery.enterLottery(collection_address, token_id[0], {"from": account})
    tx.wait(1)
    print(
        "Entered the NFT lottery with collection address {} and token id {} owner of NFT {}".format(
            collection_address, token_id[0], account.address
        )
    )
    player = lottery.getPlayer(0)
    # Assert
    assert player == account
    assert lottery.s_sessionTreasury(0)[0] == collection_address
    assert lottery.s_sessionTreasury(0)[1] == token_id[0]
    assert lottery.s_sessionTreasury(0)[2] == account.address
    # Test events, 1st event is 'Approval', 2nd event is 'Transfer', 3rd is 'LotteryEnter'
    assert tx.events[1].name == "LotteryEnter"
    assert tx.events[1]["player"] == account.address
    assert tx.events[1]["collectionAddress"] == collection_address
    assert tx.events[1]["tokenId"] == token_id[0]


def test_can_enter_unless_lottery_active():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
    account = get_account()
    (lottery, token) = deploy_lottery()
    collection_address = token.address
    # Time travel on local evm development, move time += interval and mine new block
    chain.sleep(lottery.getInterval() + 1)
    # Mining a new block otherwise timetravel irrelavant
    chain.mine()
    # Act
    with pytest.raises(exceptions.VirtualMachineError):
        lottery.enterLottery(collection_address, token_id[0], {"from": account})


def test_can_pick_winner():
    # Arrange
    # if network.show_active is in LOCAL_BLOCKCHAIN_DEVELOPMENT:
    #     pytest.skip()
    account = get_account()
    (lottery, token) = deploy_lottery()
    collection_address = token.address
    # Act
    tx = token._safeMint(account.address, 0, {"from": account})
    tx.wait(1)
    # tx = token._safeMint(account.address, 1, {"from": account})
    # tx.wait(1)
    tx = token.setApprovalForAll(lottery.address, True, {"from": account})
    tx.wait(1)
    tx = lottery.enterLottery(collection_address, token_id[0], {"from": account})
    tx.wait(1)
    # tx = lottery.enterLottery(collection_address, token_id[1], {"from": account})
    # tx.wait(1)
    # Time travel on local evm development, move time += interval and mine new block
    chain.sleep(lottery.getInterval() + 1)
    # Mining a new block otherwise timetravel irrelavant
    chain.mine()
    # performUpKeep will kick in as checkUpKeep is true (interval time passed, players>0, treasury>0)
    # Sleep for 3 minutes for getting random number from chainlink node
    # Pretending to be chainlink's node and calling performUpKeep
    tx = lottery.performUpkeep(bytes(), {"from": account})
    tx.wait(1)
    time.sleep(180)
    expected_winner = account.address
    # Assert
    assert lottery.getRecentWinner() == expected_winner


def test_distribute_tokens():
    # Arrange
    account = get_account()
    (lottery, token) = deploy_lottery()
    collection_address = token.address
    # Act
    # Sets contract as operator to spend all wallet's token on his behalf
    tx = token.setApprovalForAll(lottery.address, True, {"from": account})
    tx.wait(1)
    # enter with multiple nft's from wallet to check transfer back from contract
    for id in token_id:
        print(
            f"Approved to spend {collection_address} - {token_id[id]} to contract: {token.getApproved(token_id[id])}!"
        )
        tx = lottery.enterLottery(collection_address, token_id[id], {"from": account})
        tx.wait(1)
        print(f"Enter to NFT Lottery with token: {collection_address + ' ' + token_id[id] }")
    # Assert
