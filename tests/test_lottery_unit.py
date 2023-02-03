from brownie import network, config, exceptions
from scripts.helpful_scripts import (
    get_account,
    get_contract,
    LOCAL_BLOCKCHAIN_DEVELOPMENT,
    fund_with_link,
)
from scripts.deploy_lottery import deploy_lottery
import pytest
from web3 import Web3


def test_get_entrance_fee():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()  # unit test will be applied to development networks only
    account = get_account()
    lottery = deploy_lottery()
    # Act
    expected_entrance_fee = Web3.toWei(0.025, "ether")
    entrance_fee = lottery.getEntranceFee()
    # Assert
    # expected: eth price in usd / entrance fee
    assert entrance_fee == expected_entrance_fee


def test_can_enter_unless_started():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
    account = get_account()
    lottery = deploy_lottery()
    # Act / Assert
    with pytest.raises(exceptions.VirtualMachineError):
        lottery.enter({"from": account, "value": lottery.getEntranceFee()})


def test_can_start_and_enter_lottery():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
    account = get_account()
    lottery = deploy_lottery()
    # Act
    lottery.startLottery({"from": account})
    lottery.enter({"from": account, "value": lottery.getEntranceFee()})
    # Assert
    assert (
        lottery.players(0) == account
    )  # making sure the player added to the players array


def test_can_end_lottery():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
    account = get_account()
    lottery = deploy_lottery()
    # Act / Assert
    with pytest.raises(exceptions.VirtualMachineError):
        lottery.endLottery({"from": account})


def test_can_pick_winner():
    # Arrange
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
    # Act
    account = get_account()
    lottery = deploy_lottery()
    lottery.startLottery({"from": account})
    lottery.enter({"from": account, "value": lottery.getEntranceFee()})
    lottery.enter({"from": get_account(index=1), "value": lottery.getEntranceFee()})
    lottery.enter({"from": get_account(index=2), "value": lottery.getEntranceFee()})
    fund_with_link(lottery.address)
    transaction = lottery.endLottery({"from": account})
    # Preparing in order to act as a vrf coordinator since we are on local development
    requestId = transaction.events["requestedRandomness"][
        "requestId"
    ]  # Get the request ID from the emitted event via contract
    STATIC_RNG = 777  # To be used as our "random number"
    # Calling "callBackWithRandomness" function from vrf to send "777" as the random to our fullfilRandomness func in our contract
    get_contract("vrf_coordinator").callBackWithRandomness(
        requestId, STATIC_RNG, lottery.address, {"from": account}
    )
    # 777 % 3 == 0 -> winner will be players[0] which is our first joined participant "account"
    initiated_balance = account.balance()
    lottery_balance = lottery.balance()
    # Assert
    assert lottery.recentWinner() == account
    assert lottery.balance() == 0
    assert account.balance() == initiated_balance + lottery_balance
