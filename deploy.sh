#!/bin/bash

# Check if forge is available
if ! command -v "forge" &> /dev/null; then
    echo "Error: forge is not installed or not found in PATH."
    exit 1
fi

# Check if the user provided an argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <chain-name>"
    echo
    echo "Options:"
    echo "  --simulate               Simulate the deployment but do not broadcast it to the blockchain"
    exit 1
fi

if [ -f .env ]; then
    source .env
fi

RPC_URL=""

case $1 in
    "optimism")
        if [ "$MODE" != "mainnet" ]; then
            echo "Trying to deploy to Optimism mainnet but mode is not set to mainnet in .env file"
            exit 1
        fi

        RPC_URL=$OPTIMISM_RPC_URL
        echo "Deploying to Optimism Mainnet"
        ;;
    "arbitrum")
        if [ "$MODE" != "mainnet" ]; then
            echo "Trying to deploy to Arbitrum mainnet but mode is not set to mainnet in .env file"
            exit 1
        fi

        RPC_URL=$ARBITRUM_RPC_URL
        echo "Deploying to Arbitrum Mainnet"
        ;;
    "eth-sepolia")
        RPC_URL=$ETH_SEPOLIA_RPC_URL
        echo "Deploying to Ethereum Sepolia Testnet"
        ;;
    "op-sepolia")
        RPC_URL=$OP_SEPOLIA_RPC_URL
        echo "Deploying to Optimism Sepolia Testnet"
        ;;
    "base-sepolia")
        RPC_URL=$BASE_SEPOLIA_RPC_URL
        echo "Deploying to Base Sepolia Testnet"
        ;;
    "arb-sepolia")
        RPC_URL=$ARB_SEPOLIA_RPC_URL
        echo "Deploying to Arbitrum Sepolia Testnet"
        ;;
    "scroll-sepolia")
        RPC_URL=$SCROLL_SEPOLIA_RPC_URL
        echo "Deploying to Scroll Sepolia Testnet"
        ;;
    *)
        echo "Chain not implemented"
        exit 1
        ;;
esac

if [ "$2" == "--simulate" ]; then
    forge script script/Deploy.s.sol:SliceCoreDeployer --rpc-url $RPC_URL --sender $SENDER
elif [ "$2" == "--verify" ]; then
    forge script script/Deploy.s.sol:SliceCoreDeployer --rpc-url $RPC_URL --broadcast --sender $SENDER --etherscan-api-key $ETHERSCAN_API_KEY --verify 
else
    forge script script/Deploy.s.sol:SliceCoreDeployer --rpc-url $RPC_URL --broadcast --sender $SENDER
fi


