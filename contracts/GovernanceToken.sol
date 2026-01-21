// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITreasury {
    function deposit() external payable;
    function withdrawTo(address recipient, uint256 amount) external;
}

/**
 * @title GovernanceToken
 * @dev ERC20 Token backed 1:1 by ETH. Used for voting in CryptoVentures DAO.
 * Users deposit ETH to mint tokens and burn tokens to withdraw ETH.
 * Funds are forwarded to the Treasury contract.
 */
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    ITreasury public treasury;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(msg.sender) {}

    /**
     * @dev Set the Treasury address. Only callable by owner (could be Timelock later).
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        emit TreasuryUpdated(address(treasury), _treasury);
        treasury = ITreasury(_treasury);
    }

    /**
     * @dev Deposit ETH to mint Governance Tokens 1:1.
     * ETH is forwarded to the Treasury.
     */
    function deposit() external payable {
        require(msg.value > 0, "Amount must be greater than 0");
        require(address(treasury) != address(0), "Treasury not set");

        // Mint tokens to sender
        _mint(msg.sender, msg.value);

        // Forward ETH to Treasury
        treasury.deposit{value: msg.value}();

        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Burn tokens to withdraw ETH 1:1.
     * ETH is pulled from the Treasury.
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(address(treasury) != address(0), "Treasury not set");

        // Burn tokens from sender
        _burn(msg.sender, amount);

        // Request ETH from Treasury
        treasury.withdrawTo(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    // Overrides required by Solidity
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view override returns (string memory) {
        return "mode=timestamp";
    }
}
