
# Calculating the Slice token share for a given user
Calculate the slice token share for a given user based on all the commitments of various underlying assets for a given strategy.   

## Definitions:
- *USA*: Amount of slice tokens the user will receive after pulling token shares for a given commitment strategy
- *USS*: User Slice token share for a given commitment strategy    
- *TS_usd*: Slice token price in USD   
- *TSV_usd*: Total Slice token minted value in USD
- *TUC_usd*: Total user commitments value in USD   

- *p_usd*: Position (underlying asset) price in USD   
- *pUnits*: Amount of the underlying asset in a slice token
- *numPositions*: Number of positions in a slice token   
- *numComms*: Number of commitments made by a user to a strategy   
- *sMinted*: Slice tokens minted as the result of commitment strategy execution     
- *comm*: Amount of units committed of a given position to a strategy
    
## Formulas

<br>

The amount of slice tokens the user receives is given by:

$$
USS * sMinted = USA
$$

The user's slice token share is given by:    

$$
\frac{TSVusd}{TUCusd} = USS
$$
    
The USD price of a slice token is given by:   

$$
\sum_{i=1}^{numPositions} pUSD * pUnits = TSusd
$$    
    
The USD value of the total slice tokens minted is given by:   

$$
TSusd * sMinted = TSVusd
$$
   
The totalUSD value of a user's commitments to a strategy is given by:   

$$
\sum_{i=1}^{numComms} comm * pUSD = TUCusd
$$


## Example: 
- Slice token contains 1 BTC and 20 ETH as underlying assets (positions). 
- BTC is 60,000 USD
- ETH is 3000 USD
- Commitment strategy has a mint target of 2 Slice tokens
- User commits 40,000 USD worth of BTC an 20,000 USD worth of ETH
- What is *USS* and *USA*?

### Step 1: Calculate the Slice token price in USD (*TS_usd*)

Each Slice token consists of 1 BTC and 20 ETH:

$$
TS_{USD} = (1 \times 60,000) + (20 \times 3,000) = 60,000 + 60,000 = 120,000 \text{ USD}
$$

### Step 2: Calculate the total value of Slice tokens minted in USD (*TSV_usd*)

Given that the strategy mints 2 Slice tokens:

$$
TSV_{USD} = TS_{USD} \times s_{Minted} = 120,000 \times 2 = 240,000 \text{ USD}
$$

### Step 3: Calculate the total value of the user's commitments in USD (*TUC_usd*)

The user has committed 40,000 USD worth of BTC and 20,000 USD worth of ETH:   

$$
TUC_{USD} = comm_{BTC} + comm_{ETH} = 40{,}000 + 20{,}000 = 60{,}000 \ USD
$$

### Step 4: Calculate the User Slice token share (*USS*)

Finally, the User Slice token share is given by:

$$
USS = \frac{TUC_{USD}}{TSV_{USD}} = \frac{60,000}{240,000} = 0.25
$$

So the amount the user receives equals:

$$
USA = 0.25 * 2 = 0.5
$$

### Conclusion:

The user's slice token share (*USS*) is **0.25**. This means the user owns 25% of the total slice tokens minted for this strategy. That translates to (*USA*) **0.5** Slice tokens received.
