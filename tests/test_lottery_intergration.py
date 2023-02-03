from brownie import Lottery, network
from scripts.helpful_scripts import get_account, LOCAL_BLOCKCHAIN_DEVELOPMENT, fund_with_link
from scripts.deploy_lottery import deploy_lottery
import pytest
import time

def test_can_pick_winner():
    if network.show_active() in LOCAL_BLOCKCHAIN_DEVELOPMENT:
        pytest.skip()
    # Arrange
    account = get_account()
    lottery = deploy_lottery()
    # Act
    lottery.startLottery({"from": account})
    lottery.enter({"from": account, "value": lottery.getEntranceFee()})
    lottery.enter({"from": account, "value": lottery.getEntranceFee()})
    fund_with_link(lottery.address)
    lottery.endLottery({"from": account})
    initiated_account_balance = account.balance()
    lottery_balance = lottery.balance()
    time.sleep(180)
    # Assert
    assert lottery.recentWinner() == account
    assert lottery.balance() == 0

        
    
    

    

