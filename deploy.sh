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
    "eth-sepolia")
        RPC_URL=$ETH_SEPOLIA_RPC_URL
        echo "Deploying to Ethereum Sepolia Testnet"
        ;;
    "op-sepolia")
        RPC_URL=$OP_SEPOLIA_RPC_URL
        echo "Deploying to Optimism Sepolia Testnet"
        ;;
    *)
        echo "Chain not implemented"
        exit 1
        ;;
esac

if [ "$2" == "--simulate" ]; then
    forge script script/Deploy.s.sol:SliceCoreDeployer --rpc-url $RPC_URL --sender $SENDER
else
    forge script script/Deploy.s.sol:SliceCoreDeployer --rpc-url $RPC_URL --broadcast --sender $SENDER
fi


