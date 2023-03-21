from brownie import network, config, exceptions
from scripts.helpful_scripts import get_account, LOCAL_BLOCKCHAIN_DEVELOPMENT, FORKED_LOCAL_ENVOIRMENT
import pytest
from scripts.deploy import deploy_lottery

collection_address = "0x1c2e8135f75Eb37D18680B3AB6ba1b1a8dEe8f12"
token_id = [0, 1]


def test_can_join_lottery():
    # Arrange
    # if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
    #     pytest.skip()
    account = get_account()
    (lottery, token) = deploy_lottery(collection_address)
    # Act
    tx = token.approve(lottery.address, token_id[0], {"from": account})
    tx.wait(1)
    print(f"Approved to spend {collection_address + '-' + token_id[0]} to contract: {token.getApproved(token_id[0])}!")
    tx = lottery.enterLottery(collection_address, token_id[0], {"from": account})
    tx.wait(1)
    player = lottery.getPlayer(0)
    # Assert
    assert player == account
    assert lottery.s_treasury(0)[0] == collection_address
    assert lottery.s_treasury(0)[1] == token_id[0]
    assert lottery.s_treasury(0)[2] == account.address


def test_can_enter_unless_lottery_active():
    # Arrange
    # if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
    #     pytest.skip()
    account = get_account()
    (lottery, token) = deploy_lottery(collection_address)
    # To be tested only if Lottery Interval is in it's closed state (calculating winner)
    if lottery.getLotteryState() == 0:
        pytest.skip("Lottery is active, can't test enter unless active!")
    # Act
    with pytest.raises(exceptions.VirtualMachineError):
        lottery.enterLottery(collection_address, token_id[0], {"from": account})


def test_transfer_all_tokens():
    # Arrange
    account = get_account()
    (lottery, token) = deploy_lottery(collection_address)
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
