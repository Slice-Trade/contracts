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

![Slice Smart Contract Architecture](https://github.com/Slice-Trade/contracts/assets/44027725/da210997-63bf-4078-9191-9f493c7b8bad)

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

![Slice Smart Contract Architecture (1)](https://github.com/Slice-Trade/contracts/assets/44027725/d952116a-4ab7-4a9f-8754-c28fd377ef45)

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

![Slice Smart Contract Architecture (2)](https://github.com/Slice-Trade/contracts/assets/44027725/8b1682b4-3087-4fc5-9e55-c1f46c4e55fe)

## Redeem

In the redeem step, the owner of a Slice token is able to exchange a Slice token for the underlying assets the Slice token represents. 

The redeem steps are as follows:

- user calls the `redeem()` function on the `SliceToken.sol` contract using the front end
- token contract locks the token (so it can’t be transferred once in redeem state)
- all the underlying assets are transferred to the user’s wallet
- when all redeem successful notifications are received, the token is burned

![Slice Smart Contract Architecture (3)](https://github.com/Slice-Trade/contracts/assets/44027725/ddb78d4a-4227-43c1-a24c-7277e121d925)     


## Testnet addresses:

SEPOLIA:    
Routerporcessor: 0xF4514d34db7BE65a195C05791B2e954bE006b5DF    

SushiXSwap: 0x32F34391965A8e9322194edA50013af19b866227    

Stargateadapter: 0xC2216FCdf9bb3a40D20eD2E17632fe5AdFd4aB63    

ChainInfo: 0x3187F6AC207c6c58031Abc018d74399c0a8860AC    

SliceCore: 0xb9Ab7c5661f03852e899D3b78C32325F0da4030f    

Pool: 0xa810997Ed1A090137EdBa4805998b5BBb0A72275    

USDC: 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590    

     
OP SEPOLIA:    
Routeprocessor: 0xd5Cc9D2EB25667a7A6d5c34da08A7E55B17729F4    

SushiXSwap: 0x6C1aeA2C4933f040007a43Bc5683B0e068452c46    

Stargateadapter: 0x2B798E5a0cE8018EDd5532fF4899E2f241271ab0    

Chain info: 0xB1c883daf4ed666aa7caDC3f8dD0180addE0C3ba    

SliceCore: 0xA2264f1AE4aB3D1E23809735be08fAc307Da3f31    

SliceToken: 0x78C192f53307e0180E8dd23e291a145F422884A1    

USDC: 0x488327236B65C61A6c083e8d811a4E0D3d1D4268    
