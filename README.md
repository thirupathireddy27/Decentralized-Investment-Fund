# Decentralized Investment Fund Governance System

A sophisticated DAO governance framework designed for investment funds, featuring **Quadratic Voting**, **Multi-Tier Proposal Workflows**, and **Secure ETH-Backed Staking**.

## 🚀 Overview

This system allows participating members to manage a collective treasury by staking ETH for governance tokens. It mitigates "Whale Dominance" through quadratic voting power calculations and ensures that high-impact decisions undergo stricter scrutiny via tiered quorum and delay requirements.

### Key Features

- **ETH-Baked Governance Token**: 1:1 backed by ETH. Stake/Unstake at any time.
- **Anti-Whale Quadratic Voting**: Voting power = sqrt(tokens held), reducing the influence of large holders.
- **Multi-Tier Proposals**:
  - **High Conviction**: 20% Quorum, 2-day Timelock delay.
  - **Experimental**: 10% Quorum, 1-day Timelock delay.
  - **Operational**: 4% Quorum, 6-hour Timelock delay.
- **Automated Treasury Management**: Secure fund releases based on passed proposals.

---

## 🏗 Architecture

### Smart Contracts

1.  **`GovernanceToken.sol`**: An ERC20 token with `Votes` and `Permit` extensions. It serves as the "Stalking" mechanism where users lock ETH to gain proportional (quadratic) voting power.
2.  **`Treasury.sol`**: The DAO's vault. It holds all staked ETH and handles programmatic fund releases via the `releaseFunds` function, restricted to the Timelock.
3.  **`TimeLock.sol`**: A standard OpenZeppelin TimelockController that enforces execution delays after a proposal has passed.
4.  **`CryptoVenturesGovernance.sol`**: The brain of the DAO. Manages proposal lifecycles, tiered configurations, and voting power overrides.

---

## 🛠 Setup and Installation

### Prerequisites
- Node.js v18+
- Hardhat

### Installation
```bash
npm install
```

### Compilation
```bash
npx hardhat compile
```

### Run Tests
```bash
npx hardhat test
```

### Deployment (Local)
```bash
npx hardhat run scripts/deploy.js
```

### Seeding (Demo Data)
```bash
npx hardhat run scripts/seed.js
```

---

## 📈 Voting Logic (Quadratic Power)

Unlike standard 1-token-1-vote systems, this DAO uses a **Square Root** function to calculate voting power:

| Tokens Held | Standard Votes | Quadratic Votes (Power) |
|-------------|----------------|-------------------------|
| 1           | 1              | 1                       |
| 100         | 100            | 10                      |
| 10,000      | 10,000         | 100                     |

This ensures that while larger holders still have more influence, they cannot easily overrule a broad consensus of smaller stakeholders.

---

## 🔒 Security

- **Time-Locked Execution**: All fund releases are subject to a minimum delay, protecting against "flash loan" governance attacks.
- **Role-Based Access Control**: Strict `AccessControl` on the Treasury ensures only the DAO (via Timelock) can move funds.
- **Transparent Backing**: Every governance token is redeemable for 1 ETH, guaranteed by the contract logic.
