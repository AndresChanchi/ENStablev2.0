-include .env

# --- Variables ---
# Use '?' to allow overriding from the command line, e.g., make test-fork V=-vv
V        ?= -vvv
RPC      := $(UNICHAIN_SEPOLIA_RPC_URL)
SENDER   := 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
ACCOUNT  := agent-mockup-hackaton

# --- Phony Targets (Ensures shell autocompletion works for all commands) ---
.PHONY: build test-local test-fork coverage \
        deploy-unichain mine-hook deploy-fork deploy-all \
        clean anvil help

# Compilation and Build
build:
	forge build

# Local Testing (Anvil)
test-local:
	forge test --fork-url http://127.0.0.1:8545 $(V)

# Integration Testing (Unichain Fork)
test-fork:
	forge test --fork-url $(RPC) $(V)

# Coverage Analysis
coverage:
	forge coverage --report debug > coverage.txt

# Secure Deployment (Interactive Wallet)
# Utilizing the pre-decrypted 'agent-mockup-hackaton' keystore account
deploy-unichain:
	forge script script/DeployIdentityVault.s.sol \
		--rpc-url $(RPC) \
		--account $(ACCOUNT) \
		--sender $(SENDER) \
		--broadcast \
		-vvvv

# Mine Hook Salt: Find the necessary salt for Hook permissions on Unichain
mine-hook:
	forge script script/MineEnstableHook.s.sol $(V)

# Deployment simulation on Unichain Fork (Without spending real gas)
# This allows checking if the Hook and Vault integrate correctly with the real PoolManager
deploy-fork:
	forge script script/DeployFullSystem.s.sol \
		--fork-url $(RPC) \
		--sender $(SENDER) \
		-vvvv

# Total Deployment (Mining + Hook + Vault)
deploy-all:
	forge script script/DeployFullSystem.s.sol \
		--rpc-url $(RPC) \
		--account $(ACCOUNT) \
		--sender $(SENDER) \
		--broadcast \
		-vvvv

clean:
	forge clean
