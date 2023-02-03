from brownie import Lottery, config, network, Lottery
from scripts.helpful_scripts import get_account, get_contract, fund_with_link
import time
import yaml
import json
import os
import shutil

def deploy_lottery(front_end_update=False):
    account = get_account()
    lottery = Lottery.deploy(get_contract("eth_usd_price_feed").address, 
    get_contract("vrf_coordinator").address, 
    get_contract("link_token").address,
    config["networks"][network.show_active()]["fee"], 
    config["networks"][network.show_active()]["key_hash"],
    {"from": account},
    publish_source = config["networks"][network.show_active()].get("verify", False))
    if front_end_update:
        update_front_end()
    return lottery
 
def start_lottery():
    account = get_account()
    lottery = Lottery[-1]   # picking up latest Lottery contract
    lottery.startLottery({"from": account})

def enter_lottery():
    account = get_account()
    lottery = Lottery[-1]
    value = lottery.getEntranceFee() + 100000     # adding some value above the entrance fee to enter the lottery
    tx = lottery.enter({"from": account, "value": value})
    tx.wait(1)
    print("You entered the Lottery!!")

def end_lottery():
    account = get_account()
    lottery = Lottery[-1]
    # fund the contract with LINK
    # end lottery
    tx = fund_with_link(lottery.address)
    tx.wait(1)
    ending_lottery = lottery.endLottery({"from": account})
    ending_lottery.wait(1)
    print("Lottery ended!!")
    time.sleep(240)
    print(f"The winner is {lottery.recentWinner()}")

def update_front_end():
    # Sending frontend the build folder
    copy_folders_to_front_end("./build", "../nextjs-smartcontract-lottery/chain-info")
    # Sending frontend the brownie-config file in JSON format
    with open("brownie-config.yaml", "r") as brownie_config:
        config_dict = yaml.load(brownie_config, Loader=yaml.FullLoader)
        with open("../nextjs-smartcontract-lottery/brownie-config.json", "w") as brownie_config_json:
            json.dump(config_dict,brownie_config_json)
    print("Front end updated!")

def copy_folders_to_front_end(src, dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest)

def get_lottery_state():
    account = get_account()
    lottery = Lottery[-1]
    print(lottery.lottery_state({"from": account}))
    
def main(front_end_update = True):
    deploy_lottery()
    start_lottery()
    enter_lottery()
    end_lottery()