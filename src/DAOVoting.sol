// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/*
* @title DAOVoting Governace
* @author 0xNicos
* @notice 
* @dev 
*/

contract DAOVoting {
    //___________________
    // ERROR
    //___________________

    error DAOVoting__InvalidContract();
    error DAOVoting__InvalidDelay();
    error DAOVoting__InvalidToken();
    error DAOVoting__InvalidPeriod();
    error DAOVoting__InvalidAddress();
    error DAOVoting__Unauthorised();
    error DAOVoting__InvalidProposalId();
    error DAOVoting__UnauthorisedVoter();
    error DAOVoting__ProposalPending();
    error DAOVoting__ProposalEnded();
    error DAOVoting__DoubleVotingNotAllowed();
    error DAOVoting__QuorumNotReached();
    error DAOVoting__InvalidTimeLockTime();
    error DAOVoting__ProposalNotSucceeded();
    error DAOVoting__ProposalStillQueued();
    error DAOVoting__ProposalMustBeQueued();
    error DAOVoting__VoteStillActive();
    error DAOVoting__ExcutionFailed(bytes functionCalled);
    error DAOVoting__ProposalCanceled();
    error DAOVoting__ProposalIsExecuted();
    error DAOVoting__InvalidReceipts();

    //___________________
    // STRUCTS
    //___________________

    struct ProposalData {
        address proposer;
        address targetAddress;
        bytes encodedData;
        string description;
        ProposalStatus status;
        uint256 voteStartTime;
        uint256 voteEndTime;
        uint256 snapshotBlock;
        uint256 executionTimestamp;
    }

    struct VoteTally {
        uint256 totalVoteFor;
        uint256 totalVoteAgainst;
        uint256 totalAbstainFromVote;
    }

    struct VoteReceipt {
        bool hasVoted;
        uint256 voteWeight;
        VoteChoice voteChoice;
    }

    //___________________
    // STATE VARIABLES
    //___________________

    IVotes private immutable i_token;
    address private immutable i_timeLockContract;
    uint256 private immutable i_minVotingPeriod;
    uint256 private immutable i_timeLockDelay;

    uint256 private constant MINIMUM_QUORUM = 7500;
    uint256 private constant BASIS_POINT = 10000;
    uint256 private constant PROPOSAL_DELAY = 1 days;
    uint256 private constant MIN_PROPOSAL_TOKEN = 10000e8;

    uint256 private s_proposalCount;

    mapping(uint256 proposalId => ProposalData) private s_proposalDetails;
    mapping(uint256 proposalId => VoteTally) private s_voteTally;
    mapping(address voter => mapping(uint256 proposalId => VoteReceipt)) s_votersReceipts;

    //___________________
    // ENUM
    //___________________

    enum ProposalStatus {
        Pending,
        Active,
        Queued,
        Succeeded,
        Defeated,
        Abstain,
        Executed,
        Canceled
    }

    enum VoteChoice {
        voteFor,
        voteAgainst,
        AbstainFromVote
    }

    //___________________
    // EVENTS
    //___________________

    event ProposalSubmitted(
        address indexed proposal,
        address indexed targetAddress,
        bytes functionToCall,
        string description,
        uint256 votePeriod
    );
    event VoteCasted(
        address indexed voter, uint256 indexed proposalId, VoteChoice indexed voteDecision, uint256 weight
    );
    event VoteCastedWithDescription(
        address indexed voter, uint256 indexed proposalId, VoteChoice indexed voteDecision, string description
    );
    event VoteSucceeded(
        uint256 indexed proposalId,
        ProposalStatus status,
        uint256 totalVoteFor,
        uint256 totalVoteAgainst,
        uint256 totalAbstainFromVote
    );
    event VoteDefeated(
        uint256 indexed proposalId,
        ProposalStatus status,
        uint256 totalVoteFor,
        uint256 totalVoteAgainst,
        uint256 totalAbstainFromVote
    );
    event VoteAbstained(
        uint256 indexed proposalId,
        ProposalStatus status,
        uint256 totalVoteFor,
        uint256 totalVoteAgainst,
        uint256 totalAbstainFromVote
    );
    event ProposalQueued(uint256 indexed proposalId, ProposalStatus status, uint256 executedTime);
    event ProposalExcuted(
        address indexed targetAddress, uint256 proposalId, bytes functionCalled, ProposalStatus status
    );
    event ProposalCanceled(
        address indexed proposer, uint256 indexed proposalId, uint256 indexed proposalBalance, ProposalStatus status
    );

    //___________________
    // CONSTRUCTOR
    //___________________

    constructor(address token, address timeLockContract, uint256 minVotingPeriod, uint256 timeLockDelay) {
        if (token == address(0)) {
            revert DAOVoting__InvalidToken();
        }

        if (timeLockContract == address(0)) {
            revert DAOVoting__InvalidContract();
        }

        if (timeLockContract.code.length == 0) {
            revert DAOVoting__InvalidContract();
        }

        if (minVotingPeriod < 4 days) {
            revert DAOVoting__InvalidDelay();
        }

        if (timeLockDelay < 1 days) {
            revert DAOVoting__InvalidTimeLockTime();
        }

        i_token = IVotes(token);
        i_timeLockContract = timeLockContract;
        i_minVotingPeriod = minVotingPeriod;
        i_timeLockDelay = timeLockDelay;
    }

    function submitProposal(
        address targetedAddress,
        bytes calldata action,
        string memory description,
        uint256 votePeriod
    ) public {
        uint256 snapshootBlock = block.number - 1;

        if (targetedAddress == address(0)) {
            revert DAOVoting__InvalidAddress();
        }

        if (votePeriod <= i_minVotingPeriod) {
            revert DAOVoting__InvalidPeriod();
        }

        if (i_token.getPastVotes(msg.sender, snapshootBlock) < MIN_PROPOSAL_TOKEN) {
            revert DAOVoting__Unauthorised();
        }

        ProposalData memory proposalData = ProposalData({
            proposer: msg.sender,
            targetAddress: targetedAddress,
            encodedData: action,
            description: description,
            status: ProposalStatus.Pending,
            voteStartTime: block.timestamp,
            voteEndTime: block.timestamp + votePeriod,
            snapshotBlock: snapshootBlock,
            executionTimestamp: 0
        });

        VoteTally memory voteTally = VoteTally({totalVoteFor: 0, totalVoteAgainst: 0, totalAbstainFromVote: 0});

        s_proposalCount++;
        uint256 proposalId = s_proposalCount;

        s_voteTally[proposalId] = voteTally;
        s_proposalDetails[proposalId] = proposalData;

        emit ProposalSubmitted(msg.sender, targetedAddress, action, description, votePeriod);
    }

    function castVote(uint256 proposalId, VoteChoice voteChoice) public {
        ProposalData storage proposalData = s_proposalDetails[proposalId];
        VoteTally storage voteTally = s_voteTally[proposalId];
        VoteReceipt storage voteReceipts = s_votersReceipts[msg.sender][proposalId];

        uint256 weight = i_token.getPastVotes(msg.sender, proposalData.snapshotBlock);

        if (proposalData.proposer == address(0)) {
            revert DAOVoting__InvalidProposalId();
        }

        if (block.timestamp >= proposalData.voteEndTime) {
            revert DAOVoting__ProposalEnded();
        }

        if (block.timestamp < proposalData.voteStartTime + PROPOSAL_DELAY) {
            revert DAOVoting__ProposalPending();
        }

        proposalData.status = ProposalStatus.Active;

        if (voteReceipts.hasVoted) {
            revert DAOVoting__DoubleVotingNotAllowed();
        }

        if (weight == 0) {
            revert DAOVoting__UnauthorisedVoter();
        }

        if (voteChoice == VoteChoice.voteFor) {
            voteReceipts.voteChoice = VoteChoice.voteFor;
            voteTally.totalVoteFor += weight;
        } else if (voteChoice == VoteChoice.voteAgainst) {
            voteReceipts.voteChoice = VoteChoice.voteAgainst;
            voteTally.totalVoteAgainst += weight;
        } else {
            voteReceipts.voteChoice = VoteChoice.AbstainFromVote;
            voteTally.totalAbstainFromVote += weight;
        }

        voteReceipts.hasVoted = true;
        voteReceipts.voteWeight = weight;

        emit VoteCasted(msg.sender, proposalId, voteChoice, weight);
    }

    function castVoteWithReason(uint256 proposalId, VoteChoice voteChoice, string memory description) public {
        castVote(proposalId, voteChoice);

        emit VoteCastedWithDescription(msg.sender, proposalId, voteChoice, description);
    }

    function quorumReach(uint256 proposalId) public view returns (bool quorumReached) {
        VoteTally storage voteTally = s_voteTally[proposalId];
        ProposalData storage proposalData = s_proposalDetails[proposalId];

        uint256 totalVote = voteTally.totalVoteFor + voteTally.totalVoteAgainst + voteTally.totalAbstainFromVote;
        uint256 totalSupply = i_token.getPastTotalSupply(proposalData.snapshotBlock);

        uint256 minimumQuorum = (totalSupply * MINIMUM_QUORUM) / BASIS_POINT;

        quorumReached = totalVote >= minimumQuorum;

        return quorumReached;
    }

    function finalizeVote(uint256 proposalId) public {
        ProposalData storage proposalData = s_proposalDetails[proposalId];

        if (block.timestamp < proposalData.voteEndTime) {
            revert DAOVoting__VoteStillActive();
        }

        bool quorumReached = quorumReach(proposalId);
        if (!quorumReached) {
            revert DAOVoting__QuorumNotReached();
        }

        VoteTally storage voteTally = s_voteTally[proposalId];

        if (voteTally.totalVoteFor > voteTally.totalVoteAgainst) {
            proposalData.status = ProposalStatus.Succeeded;
            emit VoteSucceeded(
                proposalId,
                ProposalStatus.Succeeded,
                voteTally.totalVoteFor,
                voteTally.totalVoteAgainst,
                voteTally.totalAbstainFromVote
            );
        } else if (voteTally.totalVoteAgainst > voteTally.totalVoteFor) {
            proposalData.status = ProposalStatus.Defeated;
            emit VoteDefeated(
                proposalId,
                ProposalStatus.Defeated,
                voteTally.totalVoteFor,
                voteTally.totalVoteAgainst,
                voteTally.totalAbstainFromVote
            );
        } else if (voteTally.totalVoteFor == voteTally.totalVoteAgainst) {
            proposalData.status = ProposalStatus.Abstain;
            emit VoteAbstained(
                proposalId,
                ProposalStatus.Abstain,
                voteTally.totalVoteFor,
                voteTally.totalVoteAgainst,
                voteTally.totalAbstainFromVote
            );
        }
    }

    function queueProposal(uint256 proposalId) public {
        ProposalData storage proposalData = s_proposalDetails[proposalId];

        if (proposalData.status != ProposalStatus.Succeeded) {
            revert DAOVoting__ProposalNotSucceeded();
        }

        if (i_token.getPastVotes(proposalData.proposer, proposalData.snapshotBlock) < MIN_PROPOSAL_TOKEN) {
            revert DAOVoting__ProposalCanceled();
        }

        proposalData.executionTimestamp = block.timestamp + i_timeLockDelay;
        proposalData.status = ProposalStatus.Queued;

        emit ProposalQueued(proposalId, proposalData.status, proposalData.executionTimestamp);
    }

    function executeProposal(uint256 proposalId) public {
        ProposalData storage proposalData = s_proposalDetails[proposalId];

        if (proposalData.status != ProposalStatus.Queued) {
            revert DAOVoting__ProposalMustBeQueued();
        }

        if (block.timestamp < proposalData.executionTimestamp) {
            revert DAOVoting__ProposalStillQueued();
        }

        uint256 proposerBalance = i_token.getPastVotes(proposalData.proposer, proposalData.snapshotBlock);

        if (proposerBalance < MIN_PROPOSAL_TOKEN) {
            cancelProposal(proposalId);
        }

        if (proposerBalance >= MIN_PROPOSAL_TOKEN) {
            proposalData.status = ProposalStatus.Executed;

            (bool success, bytes memory returnedData) =
                proposalData.targetAddress.call{value: 0}(proposalData.encodedData);
            if (success) {
                emit ProposalExcuted(
                    proposalData.targetAddress, proposalId, proposalData.encodedData, proposalData.status
                );
            } else {
                revert DAOVoting__ExcutionFailed(abi.encode(returnedData));
            }
        }
    }

    function cancelProposal(uint256 proposalId) public {
        ProposalData storage proposalData = s_proposalDetails[proposalId];

        uint256 proposerBalance = i_token.getPastVotes(proposalData.proposer, proposalData.snapshotBlock);

        if (proposalData.status == ProposalStatus.Executed) {
            revert DAOVoting__ProposalIsExecuted();
        }

        proposalData.status = ProposalStatus.Canceled;

        emit ProposalCanceled(proposalData.proposer, proposalId, proposerBalance, proposalData.status);
    }

    function state(uint256 proposalId) external view returns (ProposalStatus) {
        ProposalData storage proposalData = s_proposalDetails[proposalId];

        if (proposalData.proposer == address(0)) {
            revert DAOVoting__InvalidProposalId();
        }

        return proposalData.status;
    }

    function getProposal(uint256 proposalId) external view returns (ProposalData memory) {
        ProposalData memory proposalData = s_proposalDetails[proposalId];

        if (proposalData.proposer == address(0)) {
            revert DAOVoting__InvalidProposalId();
        }

        return proposalData;
    }

    function getReceipts(address voter, uint256 proposalId) external view returns (VoteReceipt memory) {
        VoteReceipt memory voteReceipts = s_votersReceipts[voter][proposalId];

        if (!voteReceipts.hasVoted) {
            revert DAOVoting__InvalidReceipts();
        }

        return voteReceipts;
    }

    //___________________
    // Getters Functions
    //___________________

    function getMinimumVotingPeriod() external view returns (uint256) {
        return i_minVotingPeriod;
    }

    function getTimeLockDelay() external view returns (uint256) {
        return i_timeLockDelay;
    }

    function getTokenAddress() external view returns (address) {
        return address(i_token);
    }

    function getTimeLockContractAddr() external view returns (address) {
        return i_timeLockContract;
    }

    function getProposalCount() external view returns (uint256) {
        return s_proposalCount;
    }

    function getVoteTally(uint256 proposalId) external view returns (VoteTally memory) {
        return s_voteTally[proposalId];
    }

    function getVoterWeight(address voter, uint256 proposalId) external view returns (uint256) {
        ProposalData memory proposalData = s_proposalDetails[proposalId];
        uint256 weight = i_token.getPastVotes(voter, proposalData.snapshotBlock);

        return weight;
    }
}
