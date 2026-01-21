// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title TimeLock
 * @dev Custom TimelockController for CryptoVentures DAO.
 * Enforces execution delays and role-based execution of approved proposals.
 */
contract TimeLock is TimelockController {
    /**
     * @notice Initializes the Timelock with roles and delay.
     * @param minDelay The minimum delay in seconds required for execution.
     * @param proposers List of addresses allowed to propose.
     * @param executors List of addresses allowed to execute.
     * @param admin Role admin for the timelock.
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
