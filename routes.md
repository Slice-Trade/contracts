This basically trades 75% for WETH from USDC   
Sends that WETH to the WETH WBTC pool    
    
Then to trades the remaining USDC to another USDC coin    
Sends that USDC2 to the route processor    
    
Trades that USDC2 to WETH    
Sends that WETH to the WETH WBTC pool    
    
trades the weth to WBTC and sends it to the user address    
    
process user erc: 02     
token in (usdc1): FF970A61A04b1cA14834A43f5dE4533eBDDB5CC8    
number of routes in swap: 02    
share of the total amount in to send to pool: bfff    
isv2: 01    
pool address: 15E444da5b343c5A0931f5d3e85D158d1efC3D40 (USDC1 to WETH)    
direction: 00    
to (Uni pool - WBTC - WETH): 515e252b2b5c22b4b2b6Df66c2eBeeA871AA4d69    
    
NEXT Trade:    
share of the total: ffff    
pool type - uni v3: 01    
pool: CDA3B7BEc56DbB562453231F142F63D3B00f8EB3 (USDC1 to USDC2)    
direction: 00    
to (route processor): 544bA588efD839d2692Fc31EA991cD39993c135F    
    
process user erc: 01    
token in (USDC2): af88d065e77c8cC2239327C5EDb3A432268e5831    
    
number of routes in swap: 01    
share of the total amount in to send to pool: ffff    
is V2: 01    
pool address: f3Eb87C1F6020982173C908E7eB31aA66c1f0296 (WETH - USDC2)    
direction: 00    
to (UNI pool - WBTC - WETH): 515e252b2b5c22b4b2b6Df66c2eBeeA871AA4d69    
    
command code Process one pool: 04    
token in (WETH): 82aF49447D8a07e3bd95BD0d56f35241523fBab1    
pool type UNIv2: 00    
pool address: 515e252b2b5c22b4b2b6Df66c2eBeeA871AA4d69 (WBTC - WETH)    
direction: 00    
to: 1c46D242755040a0032505fD33C6e8b83293a332    
    
000bb8 


ETH USDC TO OP WBTC:


process user erc: 02
token in (USDC): 7F5c764cBc14f9669B88837ca1490cCa17c31607
number of routes in swap: 01
share of the total: ffff
isv2: 01
pool address: A7BB0d95C6BA0ed0aCA70C503B34BC7108589A47
direction: 00
to: 1c46D242755040a0032505fD33C6e8b83293a332
