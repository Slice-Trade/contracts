# Slice smart contracts    

# Introduction

The Slice smart contract architecture is designed to provide users with exposure to a basket of underlying assets through a single token, the Slice token. This ERC20 token represents a diversified portfolio of cryptocurrencies, with the underlying assets residing on various blockchains. Users purchase Slice tokens on a single chain using USDC. Our architecture utilizes bridging and cross-chain swaps.

Key components of the Slice architecture include two smart contracts: `SliceCore.sol` and `SliceToken.sol`. `SliceCore.sol` serves as the upgradeable core logic deployed across multiple blockchains. It facilitates cross-chain messaging and contains essential functionalities utilized by `SliceToken.sol`. `SliceToken.sol` is the ERC20 token representing the underlying assets and enabling users to access them.

The four most important smart contract interactions are the following:

- **create** new Slice tokens
- **mint** a Slice token
- **rebalance** the underlying asset positions in a Slice token
- **redeem** a Slice token for the underlying assets

## Create

In the create step an address that is allowed to create new Slice tokens calls the `createSlice()` function on the `SliceCore.sol` smart contract. What addresses are allowed to create Slice tokens will depend on the strategic/business decisions of the team (can specify anything from a single address to all addresses).

In the `createSlice()` function, the creator has to input a list of positions.
A position contains:

- the chain ID
- the token address
- the units (i.e. 0.5 ETH, 20 LINK, etc.)

The result of the create step is a new SliceToken.sol contract deployed on the main blockchain.

![Slice Smart Contract Architecture.jpg](https://prod-files-secure.s3.us-west-2.amazonaws.com/8728f3de-9ecb-4ce4-a784-e13a0a405e31/c3af7b9d-3d2f-4280-aa65-8e4320bbdf71/Slice_Smart_Contract_Architecture.jpg)

## Mint

In the mint step the end user calls the `mint()` function on the `SliceToken.sol` smart contract via the front end. 

The mint steps are as follows:

- the user approves the price of the Slice token on the USDC contract
- the user calls the mint function on the given Slice token
- the Slice core contract starts purchasing the underlying assets in the given quantities
- if an asset is local, it buys the asset on a DEX
- if the asset is cross-chain, it uses Sushi X Swap to execute a cross-chain swap and buy the given asset on Chain B
- the SushiXSwap contract calls the `onPayloadReceive()` callback on the Slice core contract on Chain B
- the Slice contract verifies the purchase --> if it is verified it sends a cross-chain message to the Slice Core contract on Chain A
- once all the signals from all chains are received, the Slice token is actually minted to the user, and any excess USDC is refunded to the user’s wallet

The result of the mint step is a new Slice token in the user's wallet on the main blockchain.

![Slice Smart Contract Architecture (1).jpg](https://prod-files-secure.s3.us-west-2.amazonaws.com/8728f3de-9ecb-4ce4-a784-e13a0a405e31/7129e03f-721e-4b2e-982b-e1846d4471f3/Slice_Smart_Contract_Architecture_(1).jpg)

## Rebalance

In the rebalance step, the address that controls the Slice token can update the units of the underlying positions. This function is to account for changes in the prices of the underlying positions. Only one address is allowed to call this function: the address that controls the Slice token. This will be the address that created the Slice token (meaning: if only the Slice team is allowed to create Slice tokens, only the Slice team will be allowed to rebalance those tokens).

The rebalance steps are as follows:

- only the address that created the Slice Token can rebalance the positions
- we calculate the amount to buy or sell for each position that needs to be rebalanced
- we go through each position, and if it is local to the main chain, we buy or sell
- if the position is on another chain, we make a cross chain message to the Slice contract on that chain
- the Slice contract on that chain buys or sells
- the Slice contract sends a confirmation to the contract on the main chain

This will change the position composition for all Slice tokens, both present and future.
A simple example: a Slice token contains 50% ETH and 50% SOL. Some time after the creation of the Slice token the price of ETH increases relative to the price of SOL, so a rebalance is necessary. 

After the rebalance, the  new distribution will be 48% ETH and 52% SOL. This rebalance will be applied to all tokens that are already minted, and all tokens that will be minted in the future. 

When and whether such a rebalance is necessary will be entirely up to the discretion of the team. (Just to give an example, in Index Coop on-chain ETFs "rebalances occur monthly based on Scalara criteria" and is applied to all tokens automatically).

![Slice Smart Contract Architecture (2).jpg](https://prod-files-secure.s3.us-west-2.amazonaws.com/8728f3de-9ecb-4ce4-a784-e13a0a405e31/c0f1de3b-2669-4854-b741-3e4eb41fed62/Slice_Smart_Contract_Architecture_(2).jpg)

## Redeem

In the redeem step, the owner of a Slice token is able to exchange a Slice token for the underlying assets the Slice token represents. 

The redeem steps are as follows:

- user calls the `redeem()` function on the `SliceToken.sol` contract using the front end
- token contract locks the token (so it can’t be transferred once in redeem state)
- all the underlying assets are transferred to the user’s wallet
- when all redeem successful notifications are received, the token is burned

![Slice Smart Contract Architecture (3).jpg](https://prod-files-secure.s3.us-west-2.amazonaws.com/8728f3de-9ecb-4ce4-a784-e13a0a405e31/0d3a7d6a-75c2-4b7e-a1c4-ac5c49b1fdbe/Slice_Smart_Contract_Architecture_(3).jpg)
