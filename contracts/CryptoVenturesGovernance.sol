// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title CryptoVenturesGovernance
 * @notice A decentralized governance system for an investment fund with multi-tier proposals and anti-whale voting.
 * @dev Implements Quadratic Voting, dynamic timelock delays, and tiered quorum requirements.
 * Note: We manually implement timelock integration instead of inheriting GovernorTimelockControl 
 * to support different execution delays for different proposal types.
 */
contract CryptoVenturesGovernance is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    using Math for uint256;

    enum ProposalType {
        HighConviction,
        Experimental,
        Operational
    }

    struct ProposalConfig {
        uint256 quorumPercentage; 
        uint256 timelockDelay;    
    }

    /// @notice The timelock controller used for proposal execution
    TimelockController private _timelock;
    
    /// @notice Mapping of proposal ID to its specific type
    mapping(uint256 => ProposalType) public proposalTypes;
    
    /// @notice Configurations for each proposal type
    mapping(ProposalType => ProposalConfig) public typeConfigs;

    /// @notice Tracks the timelock operation ID for each proposal
    mapping(uint256 => bytes32) private _timelockIds;

    /// @notice Tracks the ETA for each proposal
    mapping(uint256 => uint256) private _proposalEtas;

    event TimelockChange(address oldTimelock, address newTimelock);

    constructor(
        IVotes _token,
        TimelockController timelockAddress
    )
        Governor("CryptoVenturesGovernance")
        GovernorSettings(1 days, 1 weeks, 1e9) 
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) 
    {
        _updateTimelock(timelockAddress);

        // Multi-Tier Configs (High > Experimental > Operational)
        typeConfigs[ProposalType.HighConviction] = ProposalConfig(20, 2 days);
        typeConfigs[ProposalType.Experimental] = ProposalConfig(10, 1 days);
        typeConfigs[ProposalType.Operational] = ProposalConfig(4, 6 hours);
    }

    /**
     * @notice Returns the address of the timelock controller.
     */
    function timelock() public view virtual returns (address) {
        return address(_timelock);
    }

    /**
     * @notice Governance propose function with type selection.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType
    ) public returns (uint256) {
        uint256 proposalId = super.propose(targets, values, calldatas, description);
        proposalTypes[proposalId] = proposalType;
        return proposalId;
    }

    /**
     * @notice Fallback propose for standard interfaces.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        return propose(targets, values, calldatas, description, ProposalType.Experimental);
    }

    /**
     * @notice Quadratic Voting Power lookup.
     */
    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory params
    ) internal view override(Governor, GovernorVotes) returns (uint256) {
        uint256 rawVotes = super._getVotes(account, timepoint, params);
        return Math.sqrt(rawVotes);
    }

    /**
     * @notice All proposals require queuing in our tiered model.
     */
    function proposalNeedsQueuing(uint256 /* proposalId */) public view virtual override returns (bool) {
        return true;
    }

    /**
     * @notice Returns the execution ETA of a proposal.
     */
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposalEtas[proposalId];
    }

    /**
     * @notice Overridden state to check timelock status.
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalState currentState = super.state(proposalId);

        if (currentState != ProposalState.Queued) {
            return currentState;
        }

        bytes32 queueid = _timelockIds[proposalId];
        if (_timelock.isOperationPending(queueid)) {
            return ProposalState.Queued;
        } else if (_timelock.isOperationDone(queueid)) {
            return ProposalState.Executed;
        } else {
            return ProposalState.Canceled;
        }
    }

    /**
     * @notice Internal queuing with tiered delays.
     */
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint48) {
        ProposalType pType = proposalTypes[proposalId];
        uint256 delay = typeConfigs[pType].timelockDelay;
        
        bytes32 salt = _timelockSalt(descriptionHash);
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, salt);
        _timelock.scheduleBatch(targets, values, calldatas, 0, salt, delay);

        uint48 eta = SafeCast.toUint48(block.timestamp + delay);
        _proposalEtas[proposalId] = eta;

        return eta;
    }

    /**
     * @notice Internal execution via timelock.
     */
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override {
        _timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, _timelockSalt(descriptionHash));
        delete _timelockIds[proposalId];
        delete _proposalEtas[proposalId];
    }

    /**
     * @notice Internal cancel via timelock.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);
        bytes32 timelockId = _timelockIds[proposalId];
        if (timelockId != 0) {
            _timelock.cancel(timelockId);
            delete _timelockIds[proposalId];
            delete _proposalEtas[proposalId];
        }
        return proposalId;
    }

    /**
     * @notice Quorum reached based on tiered power percentage.
     */
    function _quorumReached(uint256 proposalId) internal view override(GovernorCountingSimple, Governor) returns (bool) {
         ProposalType pType = proposalTypes[proposalId];
         uint256 snapshot = proposalSnapshot(proposalId);
         uint256 totalSupply = token().getPastTotalSupply(snapshot);
         
         uint256 totalPower = Math.sqrt(totalSupply);
         uint256 requiredPower = (totalPower * typeConfigs[pType].quorumPercentage) / 100;
         
         (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);
         
         return (forVotes + abstainVotes + againstVotes) >= requiredPower;
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber); 
    }

    function _executor() internal view virtual override returns (address) {
        return address(_timelock);
    }

    function _timelockSalt(bytes32 descriptionHash) private view returns (bytes32) {
        return bytes20(address(this)) ^ descriptionHash;
    }

    function _updateTimelock(TimelockController newTimelock) private {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }

    // Boilerplates
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }
}
