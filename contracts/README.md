# Enstable Protocol - Agentic Liquidity Management

**AI-driven risk management and automated liquidity orchestration built on Uniswap v4.**

---

## Architecture Overview

Enstable uses an agentic approach to manage Uniswap v4 positions. The "Brain" (Hook) processes signals from an AI Agent to dynamically adjust liquidity ranges in the "Actuator" (IdentityVault).



## Documentation

For detailed information on the underlying framework, visit the [Foundry Book](https://book.getfoundry.sh/).

## Usage

### Prerequisites

This project requires **Rust 1.93.0** or newer (minimum 1.88+) for dependency management with **Soldeer**.

#### Check your Rust version:
```shell
$ rustc --version
```

#### Update Rust if necessary:

```shell
$ rustup update stable
```

### Installation

Install Uniswap v4 core, libraries, and necessary mocks via Soldeer:

```shell
$ forge soldeer install
```

### Build

Compile the project using Solidity 0.8.33:

```shell
$ make build
```

### Testing (Forking Mandatory)

Standard local execution is discouraged due to Uniswap v4 core dependency versioning (v0.8.26) and the complexity of local remappings. This project is optimized for **Unichain Sepolia Forking**, ensuring compatibility with the live `PoolManager` and official L2 state.


#### Run all tests using Unichain Sepolia Fork
```shell
$ make test-fork
```

### Deployment & Orchestration

#### 1. Mine Hook Salt

Find the deterministic salt required for the specific Uniswap v4 Hook flags (BeforeSwap, BeforeAddLiquidity, etc.):

```shell
$ make mine-hook
```

#### 2. Fork Simulation

Simulate the full system deployment (Vault + Hook) on a Unichain fork to verify integration without spending gas:

```shell
$ make deploy-fork
```

#### 3. Live Deployment

Broadcast the contracts to Unichain Sepolia using a secure keystore:

```shell
$ make deploy-all
```

### Utility Commands

**Format Code**
```shell
$ forge fmt
```

**Gas Snapshots**

```shell
$ forge snapshot --fork-url <RPC_URL>
```

**Clean Build**

```shell
$ make clean
```

**Coverage**
```shell
$ make coverage
```
## Technical Note: Why Forking?

-   **Version Harmony**: Allows our `0.8.33` architecture to interact seamlessly with Uniswap's `0.8.26` core contracts.
    
-   **Infrastructure Access**: Provides direct access to the `PoolManager` and `CREATE2` factories already deployed on Unichain.
    
-   **Accuracy**: Ensures tests account for L2-specific gas behaviors and native ETH handling.
    

----------

## Acknowledgments

-   **Framework**: Foundry (Forge, Cast, Anvil, Chisel)
    
-   **Core**: Uniswap v4
    
-   **Network**: Unichain L2