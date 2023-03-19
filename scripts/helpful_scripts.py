from brownie import Lottery, network, accounts, config, VRFCoordinatorV2Mock, MockV3Aggregator, Contract
from web3 import Web3
import os

LOCAL_BLOCKCHAIN_DEVELOPMENT = {"development", "ganache-local"}
FORKED_LOCAL_ENVOIRMENT = {"mainnet-fork", "mainnet-fork-dev"}


def get_account(index=None, id=None):
    """
    Return account based on the current active network deploying the contract.
    @para: index - for specific index from brownie accounts list
       id - for pre-loaded brownie accounts
       not provided and not on a testnet - brownie account[0]
       default - from config file based on network
    """
    if index:
        return accounts[index]
    if id:
        return accounts.load(id)
    if network.show_active() in LOCAL_BLOCKCHAIN_DEVELOPMENT or network.show_active() in FORKED_LOCAL_ENVOIRMENT:
        return accounts[0]
    return accounts.add(config["wallets"]["from_key"])


# Contract to name dictionery
contract_to_mock = {"eth_usd_price_feed": MockV3Aggregator, "vrf_coordinator": VRFCoordinatorV2Mock}


def get_contract(contract_name):
    """
    This function will grab the contract address from brownie config file if defined,
    otherwise, it will deploy a mock version of that contract and will return that
    contract.

        Args:
            contract_name (string)

        Returns:
            brownie.network.contract.ProjectNetwork - the most recently deployed version
            of that contract.
    """
    contract_type = contract_to_mock[contract_name]
    if network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT:  # working on testnet/forked net -> no need mocks
        contract_address = config["networks"][network.show_active()][contract_name]
        contract = Contract.from_abi(contract_type._name, contract_address, contract_type.abi)
    else:  # working on development network -> need to deploy mocks
        if len(contract_type) <= 0:  # if no previous mock deployed
            deploy_mocks(contract_type)
        # same as MockV3Aggregator[-1]
        contract = contract_type[-1]
    return contract


DECIMALS = 8
INITIAL_VALUE = 200000000000

BASE_FEE = Web3.toWei(0.25, "ether")
GAS_PRICE_LINK = 1e9


def deploy_mocks(contract_name):
    account = get_account()
    print("Deploying Mock!")
    MockV3Aggregator.deploy(DECIMALS, INITIAL_VALUE, {"from": account})
    VRFCoordinatorV2Mock.deploy(BASE_FEE, GAS_PRICE_LINK, {"from": account})
    print("Deployed!")
    print("--------------------------------")


VRF_SUB_FUND_AMOUT = 10


def create_subscription():
    # If working on testened, pull subscription id from config file
    if (
        network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT
        and network.show_active() not in FORKED_LOCAL_ENVOIRMENT
    ):
        return config["networks"][network.show_active()]["subscription_id"]
    # Else working on local or forked development
    # Check rather vrf mock deployed already, otherwise deploy
    if len(VRFCoordinatorV2Mock) < 0:
        vrf_coordinator = get_contract("vrf_coordinator")
    else:
        vrf_coordinator = VRFCoordinatorV2Mock[-1]
    tx = vrf_coordinator.createSubscription()
    tx.wait(1)
    subscription_id = tx.events["SubscriptionCreated"]["subId"]
    # Current VRF coordinator v2 iteration allow to fund the contract
    # mock with link without the necesery for the link token
    tx = vrf_coordinator.fundSubscription(subscription_id, VRF_SUB_FUND_AMOUT)
    tx.wait(1)
    return subscription_id


def get_publish_source():
    if network.show_active() in LOCAL_BLOCKCHAIN_DEVELOPMENT or not os.getenv("ETHERSCAN_TOKEN"):
        return False
    else:
        return True
