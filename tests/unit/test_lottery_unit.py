from brownie import network, config, exceptions, chain
from scripts.helpful_scripts import get_account, LOCAL_BLOCKCHAIN_DEVELOPMENT, FORKED_LOCAL_ENVOIRMENT
import pytest
from scripts.deploy import deploy_lottery
import time

token_id = [0, 1]


def test_can_join_lottery():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
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
    assert lottery.s_treasury(0)[0] == collection_address
    assert lottery.s_treasury(0)[1] == token_id[0]
    assert lottery.s_treasury(0)[2] == account.address
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
    collection_address = token.adress
    # Act
    tx = token.setApprovalForAll(lottery.address, True, {"from": account})
    tx.wait(1)
    tx = lottery.enterLottery(collection_address, token_id[0], {"from": account})
    tx.wait(1)
    # tx = lottery.enterLottery(collection_address, token_id[1], {"from": account})
    # tx.wait(1)
    # Sleep for the 'Interval' (4min buffer for vrf proccess) amount of the lottery as then
    # state will be changed and winner will be picked by the VRF Coordinator proccess
    time.sleep(config["networks"][network.show_active()]["interval"] + 240)
    expected_winner = account.address
    # Assert
    assert lottery.getRecentWinner() == expected_winner


def test_transfer_all_tokens():
    # Arrange
    account = get_account()
    (lottery, token) = deploy_lottery()
    collection_address = token.adress
    # Act
    # Sets contract as operator to spend all wallet's token on his behalf
    tx = token.setApprovalForAll(lottery.address, True, {"from": account})
    tx.wait(1)
    # enter with multiple nft's from wallet to check transfer back from contract
    for id in token_id:
        print(
            f"Approved to spend {collection_address + '-' + token_id[id]} to contract: {token.getApproved(token_id[id])}!"
        )
        tx = lottery.enterLottery(collection_address, token_id[id], {"from": account})
        tx.wait(1)
        print(f"Enter to NFT Lottery with token: {collection_address + ' ' + token_id[id] }")
    # Assert
