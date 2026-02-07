-include .env

# --- Variables ---
V        ?= -vvv
RPC      := $(UNICHAIN_SEPOLIA_RPC_URL)
SENDER   := 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
ACCOUNT  := agent-mockup-hackaton

.PHONY: build test test-fork coverage deploy-unichain mine-hook deploy-fork deploy-all clean help

# Default build
build:
	forge build

# PRIMARY TEST COMMAND
# Standard 'forge test' is redirected to fork-testing because Uniswap v4 
# dependencies (v0.8.26) and PoolManager state are required from Unichain.
test: test-fork

# Integration Testing via Unichain Sepolia Fork
test-fork:
	forge test --fork-url $(RPC) $(V)

# Coverage Analysis (Requires Forking to resolve external v4 calls)
coverage:
	forge coverage --fork-url $(RPC) --report debug > coverage.txt

# Secure Deployment using local keystore
deploy-unichain:
	forge script script/DeployFullSystem.s.sol \
		--rpc-url $(RPC) \
		--account $(ACCOUNT) \
		--sender $(SENDER) \
		--broadcast \
		-vvvv

# Mine Hook Salt: Finds the deterministic salt for Hook permissions
mine-hook:
	forge script script/MineEnstableHook.s.sol --fork-url $(RPC) $(V)

# Deployment Simulation (Dry-run on Fork)
deploy-fork:
	forge script script/DeployFullSystem.s.sol \
		--fork-url $(RPC) \
		--sender $(SENDER) \
		-vvvv

# Full Execution: Mine + Deploy Hook & Vault
deploy-all:
	forge script script/DeployFullSystem.s.sol \
		--rpc-url $(RPC) \
		--account $(ACCOUNT) \
		--sender $(SENDER) \
		--broadcast \
		-vvvv

clean:
	forge clean