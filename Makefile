.PHONY: all remove install build clean update test

all:
	remove install build

remove:
	rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules 

install:
	forge install foundry-rs/forge-std --no-commit && forge install openzeppelin/openzeppelin-contracts@5.0.2 --no-commit && forge install lajosdeme/lz-oapp-v2 --no-commit

build:
	forge build

clean:
	forge clean

update:
	forge update

test:
	forge test

security:
	slither .

