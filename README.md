# NexTrack: Blockchain-Based Supply Chain Tracking System

NexTrack is a decentralized supply chain management system built on blockchain technology that brings transparency and traceability to product lifecycles. It enables manufacturers, distributors, retailers, and consumers to track products from their origin to the end consumer, ensuring authenticity and building trust.

## 🌟 Features

- **Product Batch Registration**: Manufacturers can register new product batches with detailed information
- **Supply Chain Tracking**: Full traceability of products as they move through the supply chain
- **Transfer Requests**: Secure product ownership transfer with request and approval flow
- **Marketplace**: List and delist products for sale with transparent pricing
- **USDT Payments**: Integrated payment system using USDT for secure transactions
- **Governance System**: DAO-based decision making for onboarding new manufacturers
- **Product Verification**: Consumers can verify product authenticity and history

## 📋 Project Structure

```
NexTrack-foundry/
├── src/                    # Smart contract source files
│   ├── governance/         # Governance-related contracts
│   │   ├── GovToken.sol    # Governance token for DAO
│   │   ├── MyGovernor.sol  # Governor contract for voting
│   │   └── TimeLock.sol    # Timelock for governance actions
│   ├── NexTrack.sol        # Main contract for supply chain management
│   ├── USDTMock.sol        # Mock USDT token for testing
│   └── Vault.sol           # Escrow contract for payments
├── script/                 # Deployment scripts
│   ├── DeployNexTrack.s.sol # Main deployment script
│   └── HelperConfig.s.sol   # Network configuration helper
├── test/                   # Test files
│   └── NexTrackTest.t.sol  # Comprehensive test suite
├── foundry.toml            # Foundry configuration
└── README.md               # Project documentation
```

## 🔧 Technology Stack

- **Smart Contract Development**: Solidity 0.8.24
- **Development Framework**: Foundry
- **Testing**: Forge
- **Deployment**: Forge Script
- **Token Standards**: ERC20 for governance and payment tokens
- **Governance**: OpenZeppelin Governor, TimelockController

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)
- [Node.js](https://nodejs.org/) (optional, for additional tooling)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Psyphon361/nextrack-foundry.git
   cd nextrack-foundry
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Create a `.env` file in the project root with the following variables:
   ```
   ELECTRONEUM_TESTNET_RPC=https://testnet-rpc.electroneum.com
   # We'll use a keystore instead of plain text private key for security
   ```

4. Create a secure keystore for your private key (recommended for security):
   ```bash
   # This will encrypt your private key and store it securely
   cast wallet import etnDeployer --private-key your-private-key
   
   # You only need to enter your private key in plain text this one time
   # The key will be encrypted with a password you'll be prompted to create
   ```

5. When deploying, you can use the keystore instead of a plain text private key:
   ```bash
   # You'll be prompted for the password you set when creating the keystore
   forge script script/DeployNexTrack.s.sol:DeployNexTrack --account etnDeployer --rpc-url $ELECTRONEUM_TESTNET_RPC --broadcast
   ```

### Compilation

Compile the smart contracts:
```bash
forge build
```

### Testing

Run the test suite:
```bash
forge test
```

For more detailed test output:
```bash
forge test -vvvv
```

### Deployment

#### Local Deployment (Anvil)

1. Start a local Ethereum node:
   ```bash
   anvil
   ```

2. Deploy the contracts:
   ```bash
   forge script script/DeployNexTrack.s.sol:DeployNexTrack --broadcast --rpc-url http://localhost:8545
   ```

#### Testnet Deployment (Electroneum)

Deploy to Electroneum testnet using the secure keystore:
```bash
forge script script/DeployNexTrack.s.sol:DeployNexTrack --account etnDeployer --rpc-url $ELECTRONEUM_TESTNET_RPC --broadcast
```

## 📖 How It Works

### Supply Chain Flow

1. **Manufacturer Registration**: Manufacturers are onboarded through governance voting
2. **Product Batch Creation**: Registered manufacturers create product batches with details
3. **Transfer Request**: Buyers request products from sellers
4. **Payment**: Buyer deposits USDT into the vault as escrow
5. **Approval**: Seller approves the transfer request
6. **Confirmation**: Buyer confirms receipt and creates a new batch
7. **Payment Settlement**: USDT is transferred from vault to seller

### Governance

The system uses a DAO-based governance model:
- Governance token (NXT) holders can propose and vote on decisions
- Proposals go through a voting period
- Approved proposals are executed after a timelock period
- Used for onboarding new manufacturers and system upgrades

## 🔍 Contract Overview

- **NexTrack.sol**: Core contract managing product batches, transfers, and marketplace
- **Vault.sol**: Handles USDT escrow for secure payments
- **GovToken.sol**: ERC20 token with voting capabilities for governance
- **MyGovernor.sol**: Handles proposal creation, voting, and execution
- **TimeLock.sol**: Adds time delay for governance actions

## 🛠️ Development

### Adding New Features

1. Create a new branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Implement your changes and add tests

3. Run tests to ensure everything works:
   ```bash
   forge test
   ```

4. Create a pull request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgements

- [OpenZeppelin](https://openzeppelin.com/) for secure contract libraries
- [Foundry](https://book.getfoundry.sh/) for the development framework
- [Electroneum](https://electroneum.com/) for blockchain infrastructure
