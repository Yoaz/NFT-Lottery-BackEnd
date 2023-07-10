from brownie import Lottery, accounts, network, config, interface
from scripts.helpful_scripts import get_account, get_contract, create_subscription, get_publish_source
import yaml
import json
import os
import shutil


def deploy_lottery(front_end_update=False):
    account = get_account()
    lottery = Lottery.deploy(
        get_contract("eth_usd_price_feed").address,
        get_contract("vrf_coordinator").address,
        config["networks"][network.show_active()]["gas_lane"],
        create_subscription(),
        config["networks"][network.show_active()]["callback_gas_limit"],
        config["networks"][network.show_active()]["interval"],
        {"from": account},
        publish_source=False,
    )
    print(f"SUCCESS! Contract deployed at {lottery.address}")
    # token = interface.IERC721(token_address)
    token = get_contract("nft_collection")
    if front_end_update:
        update_front_end()
    return lottery, token


def transfer_token_back_to_owner(collection_address, token_id):
    account = get_account()
    lottery = Lottery[-1]
    tx = lottery.transfer(account.address, collection_address, token_id, {"from": account})
    tx.wait(1)
    print("Token {} - {} has been transfered back to {}".format(collection_address, token_id, account.address))


def update_front_end():
    # Sending frontend the build folder with all the deployments info
    copy_folders_to_front_end("./build", "../NFT Lottery FrontEnd/src/chain-info")
    # Sending frontend the brownie-config file in JSON format
    with open("brownie-config.yaml", "r") as brownie_config:
        config_dict = yaml.load(brownie_config, Loader=yaml.FullLoader)
        with open("../NFT Lottery BackEnd/brownie_config.json", "w") as brownie_config_json:
            json.dump(config_dict, brownie_config_json)
        print("Front end updated!")


def copy_folders_to_front_end(src, dest):
    """
    Function to copy folders from source to destination.

        args:
            src - source to copy from
            dest - destination to copy to
    """
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest)


def main():
    deploy_lottery()
