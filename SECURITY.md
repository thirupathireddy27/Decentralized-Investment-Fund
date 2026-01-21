# Security Considerations

## 1. Governance Attacks Mitigation

### Whale Dominance
*   **Risk**: Large capital holders dictating all decisions.
*   **Mitigation**: **Quadratic Voting**. Voting power scales with the square root of the stake. To have 10x the influence, an attacker must risk 100x the capital.

### Flash Loan Attacks
*   **Risk**: Borrowing ETH, staking, voting, and withdrawing in one transaction.
*   **Mitigation**:
    *   **Voting Delay**: The Governor enforces a `1 day` delay between snapshot and voting start. Flash loan tokens minted in block `N` cannot vote for proposals snapshotted in `N-1`.
    *   **Past Total Supply**: Quorum calculations look at the past checkpoint, ignoring instantaneous supply shocks.

### 51% Attacks
*   **Risk**: Majority takeover of treasury.
*   **Mitigation**:
    *   **Timelock**: All execution is delayed (min 6 hours, up to 2 days).
    *   **Rage Quit**: Since tokens are 1:1 liquid for ETH, minority dissenters can withdraw their funds during the timelock period if they disagree with a pending malicious proposal (before it executes).

## 2. Smart Contract Security

### Access Control
*   **Treasury**: STRICTLY controlled.
    *   `withdrawTo`: Only callable by `GovernanceToken` (automatic on burn).
    *   `releaseFunds`: Only callable by `TimeLock` (via successful vote).
    *   No admin "backdoor" to drain funds.

### Reentrancy
*   **Pattern**: Checks-Effects-Interactions pattern is strictly followed.
*   **Governor**: Uses OpenZeppelin's battle-tested libraries.

## 3. Operational Risks

### Proposal Spam
*   **Mitigation**: A `ProposalThreshold` (currently set to 0 for testing, but should be raised in production) requires a proposer to have "skin in the game".

### Deadlock
*   **Risk**: TimeLock admin keys lost.
*   **Mitigation**: The governance contract itself is the PROPOSER for the TimeLock. The system is self-governing and decentralized.

## 4. Pending Audits
*   *Note: This system has not yet undergone a third-party professional audit. Deployment to mainnet is at your own risk.*
