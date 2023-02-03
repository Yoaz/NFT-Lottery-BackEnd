from brownie import (
    accounts,
    Lottery,
    config,
    network,
    MockV3Aggregator,
    Contract,
    VRFCoordinatorMock,
    LinkToken,
)

FORKED_LOCAL_ENVOIRMENTAL = {"mainnet-fork", "mainnet-fork-dev"}
LOCAL_BLOCKCHAIN_DEVELOPMENT = {"development", "ganache-local"}


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
    if (
        network.show_active() in LOCAL_BLOCKCHAIN_DEVELOPMENT
        or network.show_active() in FORKED_LOCAL_ENVOIRMENTAL
    ):
        return accounts[0]
    return accounts.add(config["wallets"]["from_key"])


# mapping contract-key to contract-name
contract_to_mock = {
    "eth_usd_price_feed": MockV3Aggregator,
    "vrf_coordinator": VRFCoordinatorMock,
    "link_token": LinkToken,
}


def get_contract(contract_name):
    """This function will grab the contract address from brownie config file if defined,
    otherwise, it will deploy a mock version of that contract and will return that
    contract.

        Args:
            contract_name (string)

        Returns:
            brownie.network.contract.ProjectNetwork - the most recently deployed version
            of that contract.
    """
    contract_type = contract_to_mock[contract_name]
    if (
        network.show_active() not in LOCAL_BLOCKCHAIN_DEVELOPMENT
    ):  # working on testnet/forked net -> no need mocks
        contract_address = config["networks"][network.show_active()][contract_name]
        contract = Contract.from_abi(
            contract_type._name, contract_address, contract_type.abi
        )
    else:  # working on development network -> need to deploy mocks
        if len(contract_type) <= 0:  # if no previous mock deployed
            deploy_mocks(contract_type)
        # same as MockV3Aggregator[-1]
        contract = contract_type[-1]
    return contract


DECIMALS = 8
INITIAL_VALUE = 200000000000


def deploy_mocks(contract_name):
    account = get_account()
    print("Deploying Mock!")
    MockV3Aggregator.deploy(DECIMALS, INITIAL_VALUE, {"from": account})
    link_token = LinkToken.deploy({"from": account})
    VRFCoordinatorMock.deploy(link_token.address, {"from": account})
    print("Deployed!")


##
# dev fund a contract with link token
# @para contract_address = contract address to fund (required)
# @para account = in case a specific account to send from otherwise using default
# @para link_token = in case of a specific link token address to use, otherwise default
# @para value = default 0.1 LINK
def fund_with_link(
    contract_address, account=None, link_token=None, value=250000000000000000
):
    account = account if account else get_account()
    link_token = link_token if link_token else get_contract("link_token")
    tx = link_token.transfer(contract_address, value, {"from": account})
    tx.wait(1)
    print("Contract funded with LINK!!")
    return tx
