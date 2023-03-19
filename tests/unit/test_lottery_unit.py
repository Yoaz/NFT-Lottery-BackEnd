from brownie import network, config
from scripts.helpful_scripts import get_account, LOCAL_BLOCKCHAIN_DEVELOPMENT, FORKED_LOCAL_ENVOIRMENT
import pytest
from scripts.deploy import deploy_lottery


def test_can_join_lottery():
    # Arrange
    # if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
    #     pytest.skip()
    account = get_account()
    collection_address = "0x1c2e8135f75Eb37D18680B3AB6ba1b1a8dEe8f12"
    token_id = "0"
    (lottery, token) = deploy_lottery(collection_address)
    # Act
    # token = IERC721(collection_address)
    tx = token.approve(lottery.address, token_id, {"from": account})
    tx.wait(1)
    print(f"Approved to spend {collection_address + '-' + token_id} to contract: {token.getApproved(token_id)}!")
    # tx = token.safeTransfer(account.address, lottery.address, token_id, {"from": account})
    # tx.wait(1)
    tx = lottery.enterLottery(collection_address, token_id, {"from": account})
    tx.wait(1)
    # Assert
    assert lottery.s_players(0) == account
    assert lottery.s_treasury(0)[0] == collection_address
    assert lottery.s_treasury(0)[1] == token_id
    assert lottery.s_treasury(0)[2] == account.address

def test_can_enter_unless_lottery_active():
    if network.show_active() is not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()