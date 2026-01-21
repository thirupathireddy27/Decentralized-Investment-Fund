// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Treasury
 * @dev Holds DAO funds and manages allocations for different proposal types.
 */
contract Treasury is AccessControl {
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Matches ProposalType in Governance
    enum FundCategory {
        HighConviction,
        Experimental,
        Operational
    }

    // Total allocated budget for each category (The 60/30/10 split)
    mapping(FundCategory => uint256) public categoryBudgets;
    
    // Max transaction size per category (Risk Management)
    // Ensures Operational funds (fast lane) are only used for small amounts.
    mapping(FundCategory => uint256) public categoryTxLimits;
    
    // Track total spent per category
    mapping(FundCategory => uint256) public totalSpent;

    event FundsDeposited(address indexed sender, uint256 amount);
    event FundsReleased(address indexed recipient, uint256 amount, FundCategory category);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    event BudgetsUpdated(FundCategory category, uint256 newBudget, uint256 newTxLimit);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        
        // Initial Budgets (Assume 1000 ETH target raise or initial capacity)
        // HighConviction: 600 ETH (60%)
        // Experimental: 300 ETH (30%)
        // Operational: 100 ETH (10%)
        categoryBudgets[FundCategory.HighConviction] = 600 ether;
        categoryBudgets[FundCategory.Experimental] = 300 ether;
        categoryBudgets[FundCategory.Operational] = 100 ether;

        // Transaction Limits
        // HC: No limit (up to budget)
        // Exp: 50 ETH limit per bet
        // Op: 5 ETH limit per expense (Small operational expenses)
        categoryTxLimits[FundCategory.HighConviction] = 600 ether;
        categoryTxLimits[FundCategory.Experimental] = 50 ether;
        categoryTxLimits[FundCategory.Operational] = 5 ether;
    }

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Called by GovernanceToken when users deposit.
     */
    function deposit() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Release funds for an executed proposal.
     * Only callable by Timelock (EXECUTOR_ROLE).
     */
    function releaseFunds(
        address recipient,
        uint256 amount,
        FundCategory category
    ) external onlyRole(EXECUTOR_ROLE) {
        require(amount <= address(this).balance, "Insufficient Treasury Balance");
        
        // 1. Check Transaction Limit (Risk Control)
        require(amount <= categoryTxLimits[category], "Amount exceeds transaction limit for this category");

        // 2. Check Budget Allocation (Strategic Control)
        require(totalSpent[category] + amount <= categoryBudgets[category], "Category budget exceeded");

        payable(recipient).transfer(amount);
        totalSpent[category] += amount;

        emit FundsReleased(recipient, amount, category);
    }

    /**
     * @dev Withdraw funds back to user (from GovernanceToken).
     * Only callable by GovernanceToken (WITHDRAWER_ROLE).
     */
    function withdrawTo(address recipient, uint256 amount) external onlyRole(WITHDRAWER_ROLE) {
        require(amount <= address(this).balance, "Insufficient Treasury Balance");
        payable(recipient).transfer(amount);
        emit FundsWithdrawn(recipient, amount);
    }

    /**
     * @dev Update budgets and limits.
     */
    function updateCategoryConfig(FundCategory category, uint256 newBudget, uint256 newTxLimit) external onlyRole(ADMIN_ROLE) {
        categoryBudgets[category] = newBudget;
        categoryTxLimits[category] = newTxLimit;
        emit BudgetsUpdated(category, newBudget, newTxLimit);
    }

    /**
     * @dev View function to see available funds for a category.
     */
    function getCategoryBalance(FundCategory category) external view returns (uint256) {
        if (totalSpent[category] >= categoryBudgets[category]) return 0;
        return categoryBudgets[category] - totalSpent[category];
    }
}
