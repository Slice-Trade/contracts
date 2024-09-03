### Slice Token Migrator

The goal of the Slice token migrator is to open up another way of moving between slice tokens that doesn't rely on going through AMMs.

#### Example:
SliceA has 1 ETH, 1 UNI, 1 MATIC. SliceB has 1 ETH, 1 UNI, 1 WBTC. Let’s say we own 1 SliceA, and want to migrate to 1 SliceB. Here we need to provide 1 WBTC, and we will get back 1 MATIC. Our 1 SliceA should be burned, and 1 SliceB should be minted to us.

`SliceTokenMigrator` will need to have the following steps:
1. `migrateStep1()`: transfer sliceA into the contract, then call redeem on sliceA
2. `migrateStep2()`: check if redeem succeeded, if yes transfer missing assets, then mint sliceB
3. `withdraw()`: transfer out the minted slice token (sliceB) to the user, as well as the leftover assets from sliceA (1 MATIC)
