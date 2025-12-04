// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DAOVoting} from "../src/DAOVoting.sol";
import {DeployDAOVoting} from "../script/DeployDAOVoting.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {VotesMock} from "../test/mocks/VotesMock.sol";
import {MaliciousContract} from "../test/mocks/MaliciousContract.sol";

contract DAOVotingTest is Test {
    DAOVoting daoVoting;
    HelperConfig helper;
    DeployDAOVoting deployer;
    VotesMock voteMocks;

    address token;
    address timeLockContract;
    uint256 minVotingPeriod;
    uint256 timeLockDelay;

    address proposer = makeAddr("proposer");
    address targetedAddress = makeAddr("targetedAddress");
    address voter = makeAddr("voter");
    address nico = makeAddr("nico");

    uint256 private constant STARTING_PROPOSER_VOTES = 20000e8;

    uint256 private votePeriod = 10 days;

    event ProposalSubmitted(
        address indexed proposal,
        address indexed targetAddress,
        bytes functionToCall,
        string description,
        uint256 votePeriod
    );
    event VoteCasted(
        address indexed voter, uint256 indexed proposalId, DAOVoting.VoteChoice indexed voteDecision, uint256 weight
    );
    event VoteCastedWithDescription(
        address indexed voter, uint256 indexed proposalId, DAOVoting.VoteChoice indexed voteDecision, string description
    );
    event VoteSucceeded(
        uint256 indexed proposalId,
        DAOVoting.ProposalStatus status,
        uint256 totalVoteFor,
        uint256 totalVoteAgainst,
        uint256 totalAbstainFromVote
    );
    event VoteDefeated(
        uint256 indexed proposalId,
        DAOVoting.ProposalStatus status,
        uint256 totalVoteFor,
        uint256 totalVoteAgainst,
        uint256 totalAbstainFromVote
    );
    event VoteAbstained(
        uint256 indexed proposalId,
        DAOVoting.ProposalStatus status,
        uint256 totalVoteFor,
        uint256 totalVoteAgainst,
        uint256 totalAbstainFromVote
    );
    event ProposalQueued(uint256 indexed proposalId, DAOVoting.ProposalStatus status, uint256 executedTime);
    event ProposalExcuted(
        address indexed targetAddress, uint256 proposalId, bytes functionCalled, DAOVoting.ProposalStatus status
    );
    event ProposalCanceled(
        address indexed proposer,
        uint256 indexed proposalId,
        uint256 indexed proposalBalance,
        DAOVoting.ProposalStatus status
    );

    function setUp() external {
        deployer = new DeployDAOVoting();

        (daoVoting, helper) = deployer.run();

        (token, timeLockContract, minVotingPeriod, timeLockDelay) = helper.activeNetworkConfig();

        voteMocks = VotesMock(token);

        voteMocks.mint(proposer, STARTING_PROPOSER_VOTES);
        voteMocks.mint(voter, STARTING_PROPOSER_VOTES);
        voteMocks.mint(nico, STARTING_PROPOSER_VOTES);

        vm.prank(proposer);
        voteMocks.delegate(proposer, proposer);

        vm.prank(voter);
        voteMocks.delegate(voter, voter);

        vm.prank(nico);
        voteMocks.delegate(nico, nico);

        vm.roll(block.number + 2);
    }

    //_____________________
    // Modifier
    //_____________________

    modifier proposalSubmitted() {
        vm.prank(proposer);
        daoVoting.submitProposal(targetedAddress, "", "reduce fee", votePeriod);
        _;
    }

    modifier forwardTime() {
        vm.warp(block.timestamp + 1 days);
        _;
    }

    modifier voteCasted() {
        uint256 proposalId = 1;

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.prank(proposer);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        _;
    }

    //_____________________
    // constructor
    //_____________________

    function testConstructorRevertWhenTokenAddressIsZero() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidToken.selector);
        daoVoting = new DAOVoting(address(0), timeLockContract, minVotingPeriod, timeLockDelay);
    }

    function testConstructorRevertWhenTimeLockIsZeroAddress() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidContract.selector);
        new DAOVoting(token, address(0), minVotingPeriod, timeLockDelay);
    }

    function testConstructorRevertWhenTimeLockHasNoCode() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidContract.selector);
        new DAOVoting(token, proposer, minVotingPeriod, timeLockDelay);
    }

    function testConstructorRevertWhenMinVotingPeriodIsLessThan4days() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidDelay.selector);
        new DAOVoting(token, timeLockContract, 3 days, timeLockDelay);
    }

    function testConstructorRevertWhenTimeLockDelayIsBelowOneDays() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidTimeLockTime.selector);
        new DAOVoting(token, timeLockContract, minVotingPeriod, 0 days);
    }

    function testConstructorPassAndSetStates() public {
        DAOVoting dao = new DAOVoting(token, timeLockContract, minVotingPeriod, timeLockDelay);

        assertEq(dao.getMinimumVotingPeriod(), minVotingPeriod);
        assertEq(dao.getTimeLockDelay(), timeLockDelay);
        assertEq(dao.getTokenAddress(), token);
        assertEq(dao.getTimeLockContractAddr(), timeLockContract);
    }

    //_____________________
    // SubmitProposal
    //_____________________

    function testSubmitProposalRevertIfTargetAddressIsAddressZero() public {
        vm.prank(proposer);
        vm.expectRevert(DAOVoting.DAOVoting__InvalidAddress.selector);
        daoVoting.submitProposal(address(0), "", "hello word", 10 days);
    }

    function testSubmitProposalRevertIfVotingPeriodIsLessThanMinimum() public {
        vm.prank(proposer);
        vm.expectRevert(DAOVoting.DAOVoting__InvalidPeriod.selector);
        daoVoting.submitProposal(targetedAddress, "", "set value", 2 days);
    }

    function testSubmitProposalRevertIfProposerHasNoVoteAtProposedTime() public {
        address sammy = makeAddr("sammy");

        vm.prank(sammy);
        vm.expectRevert(DAOVoting.DAOVoting__Unauthorised.selector);
        daoVoting.submitProposal(targetedAddress, "", "reduce fee", 8 days);
    }

    function testSubmitProposalPassedUpdateStateAndEmitEvent(uint256 voteDuration) public {
        vm.assume(voteDuration > 8 days && voteDuration < 30 days);

        uint256 proposalId = 1;

        vm.expectEmit(true, true, true, false);
        emit ProposalSubmitted(proposer, targetedAddress, "", "reduce fee", voteDuration);

        vm.prank(proposer);
        daoVoting.submitProposal(targetedAddress, "", "reduce fee", voteDuration);

        assertEq(daoVoting.getProposal(proposalId).proposer, proposer);
        assertEq(daoVoting.getProposalCount(), 1);
    }

    //_____________________
    // CastVote
    //_____________________

    function testCastVoteRevertWhenProposalIsPending() public proposalSubmitted {
        uint256 proposalId = daoVoting.getProposalCount();

        vm.expectRevert(DAOVoting.DAOVoting__ProposalPending.selector);
        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);
    }

    function testCastVoteRevertWhenProposalEnded() public proposalSubmitted {
        uint256 proposalId = daoVoting.getProposalCount();

        vm.warp(block.timestamp + 10 days);

        vm.expectRevert(DAOVoting.DAOVoting__ProposalEnded.selector);
        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);
    }

    function testCastVoteRevertWhenProposerIsInvalid() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidProposalId.selector);
        vm.prank(proposer);
        daoVoting.castVote(10, DAOVoting.VoteChoice.AbstainFromVote);
    }

    function testCastVoteRevertWhneAlreadyVote() public proposalSubmitted {
        vm.warp(block.timestamp + 2 days);

        uint256 proposalId = daoVoting.getProposalCount();

        vm.startPrank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.expectRevert(DAOVoting.DAOVoting__DoubleVotingNotAllowed.selector);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.stopPrank();
    }

    function testCastVoteRevertWhnVoterHasNoWeight() public proposalSubmitted forwardTime {
        address attacker = makeAddr("attacker");

        uint256 proposalId = 1;

        vm.expectRevert(DAOVoting.DAOVoting__UnauthorisedVoter.selector);
        vm.prank(attacker);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.AbstainFromVote);
    }

    function testCastVotePassedAndEmitEvent() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        uint256 weight = daoVoting.getVoterWeight(nico, proposalId);

        vm.expectEmit(true, true, true, false);
        emit VoteCasted(nico, proposalId, DAOVoting.VoteChoice.voteFor, weight);

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);
    }

    function testCastVotePassedAndUpdateState() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        uint256 weight = daoVoting.getVoterWeight(nico, proposalId);

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.prank(proposer);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.AbstainFromVote);

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        assertEq(daoVoting.getVoteTally(proposalId).totalVoteFor, weight);
        assert(daoVoting.getReceipts(nico, proposalId).hasVoted == true);
        assertEq(daoVoting.getReceipts(nico, proposalId).voteWeight, weight);
        assertEq(daoVoting.getVoteTally(proposalId).totalVoteAgainst, weight);
        assertEq(daoVoting.getVoteTally(proposalId).totalAbstainFromVote, weight);
    }

    //____________________________
    // CastVoteWithDescription
    //____________________________

    function testCastVoteWithDescriptionsEmitEvents() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.expectEmit(true, true, false, false);
        emit VoteCastedWithDescription(voter, proposalId, DAOVoting.VoteChoice.voteAgainst, "fee shouldnt be reduced");

        vm.prank(voter);
        daoVoting.castVoteWithReason(proposalId, DAOVoting.VoteChoice.voteAgainst, "fee shouldnt be reduced");
    }

    //_____________________
    // QuorumReach
    //_____________________

    function testQuorumReachReturnFalseWhenQuorunIsNotReached() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        bool quorum = daoVoting.quorumReach(proposalId);

        assert(quorum == false);
    }

    function testQuroumReturnTrueWhenQuorumIsReached() public {
        uint256 proposalId = 1;
        uint256 voterLength = 103;

        for (uint256 i = 0; i < voterLength; i++) {
            address voters = makeAddr(string(abi.encodePacked("voters", i)));
            VotesMock(token).mint(voters, STARTING_PROPOSER_VOTES * 100);

            vm.prank(voters);
            VotesMock(token).delegate(voters, voters);
        }

        vm.roll(block.number + 1);

        vm.prank(proposer);
        daoVoting.submitProposal(targetedAddress, "", "reduce trnx fee", votePeriod);

        vm.warp(block.timestamp + 2 days);

        for (uint256 i = 0; i < voterLength; i++) {
            address voters = makeAddr(string(abi.encodePacked("voters", i)));

            vm.prank(voters);
            daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);
        }

        bool quorum = daoVoting.quorumReach(proposalId);
        assert(quorum == true);
    }

    //_____________________
    // FinalizeVote
    //_____________________

    function testFinaliseVoteRevertWhenVoteIsNotEnded() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.prank(nico);
        vm.expectRevert(DAOVoting.DAOVoting__VoteStillActive.selector);
        daoVoting.finalizeVote(proposalId);
    }

    function testRevertWhenQuorumIsNotReached() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 12 days);

        vm.prank(voter);
        vm.expectRevert(DAOVoting.DAOVoting__QuorumNotReached.selector);
        daoVoting.finalizeVote(proposalId);
    }

    function testFinaliseVoteUpdateStateForVoteForAndEmitEvent() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.startPrank(proposer);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.warp(block.timestamp + 11 days);

        DAOVoting.VoteTally memory tally = daoVoting.getVoteTally(proposalId);

        vm.expectEmit(true, true, false, false);
        emit VoteSucceeded(
            proposalId,
            DAOVoting.ProposalStatus.Succeeded,
            tally.totalVoteFor,
            tally.totalVoteAgainst,
            tally.totalAbstainFromVote
        );

        daoVoting.finalizeVote(proposalId);

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Succeeded);
    }

    function testFinaliseVotesUpdateStateForVoteAgainstAndEmitEvent() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.prank(proposer);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.AbstainFromVote);

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.warp(block.number + 11 days);

        DAOVoting.VoteTally memory tally = daoVoting.getVoteTally(proposalId);

        vm.expectEmit(true, true, true, false);
        emit VoteDefeated(
            proposalId,
            DAOVoting.ProposalStatus.Defeated,
            tally.totalVoteFor,
            tally.totalVoteAgainst,
            tally.totalAbstainFromVote
        );

        vm.prank(nico);
        daoVoting.finalizeVote(proposalId);

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Defeated);
    }

    function testFinaliseVoteUpdateStateAndEmitEventWhenVotIsAbstained() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.prank(proposer);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.AbstainFromVote);

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.warp(block.number + 11 days);

        DAOVoting.VoteTally memory tally = daoVoting.getVoteTally(proposalId);

        vm.expectEmit(true, true, false, false);
        emit VoteAbstained(
            proposalId,
            DAOVoting.ProposalStatus.Abstain,
            tally.totalVoteFor,
            tally.totalVoteAgainst,
            tally.totalAbstainFromVote
        );

        vm.prank(nico);
        daoVoting.finalizeVote(proposalId);

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Abstain);
    }

    //_____________________
    // QueueProposal
    //_____________________

    function testQueueProposalRevertWhenProposalDidNotSucceded() public proposalSubmitted forwardTime {
        uint256 proposalId = 1;

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.prank(proposer);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.AbstainFromVote);

        vm.prank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteAgainst);

        vm.warp(block.timestamp + 10 days);

        vm.prank(nico);
        daoVoting.finalizeVote(proposalId);

        vm.prank(voter);
        vm.expectRevert(DAOVoting.DAOVoting__ProposalNotSucceeded.selector);
        daoVoting.queueProposal(proposalId);
    }

    function testQueueTransactionPassedAndUpdateStateAndEmitEvent() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 10 days);

        vm.prank(nico);
        daoVoting.finalizeVote(proposalId);

        DAOVoting.ProposalData memory proposalData = daoVoting.getProposal(proposalId);

        vm.expectEmit(true, true, false, false);
        emit ProposalQueued(proposalId, DAOVoting.ProposalStatus.Queued, proposalData.executionTimestamp);

        vm.prank(voter);
        daoVoting.queueProposal(proposalId);

        uint256 expectedTimelockDelay = daoVoting.getTimeLockDelay() + block.timestamp;

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Queued);
        assertEq(daoVoting.getProposal(proposalId).executionTimestamp, expectedTimelockDelay);
    }

    //_____________________
    // ExecuteProposal
    //_____________________

    function testExecutionRevertWhenProposalIsNotQeued() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 10 days);

        vm.prank(voter);
        daoVoting.finalizeVote(proposalId);

        vm.expectRevert(DAOVoting.DAOVoting__ProposalMustBeQueued.selector);
        vm.prank(nico);
        daoVoting.executeProposal(proposalId);
    }

    function testExecuteTransactionRevertWhenDelayTimeIsActive() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 11 days);

        vm.prank(proposer);
        daoVoting.finalizeVote(proposalId);

        vm.prank(nico);
        daoVoting.queueProposal(proposalId);

        vm.prank(voter);
        vm.expectRevert(DAOVoting.DAOVoting__ProposalStillQueued.selector);
        daoVoting.executeProposal(proposalId);
    }

    function testExecuteTransactionPassedSetStatusEmitEvent() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 12 days);

        vm.startPrank(voter);

        daoVoting.finalizeVote(proposalId);

        daoVoting.queueProposal(proposalId);
        vm.stopPrank();

        DAOVoting.ProposalData memory data = daoVoting.getProposal(proposalId);

        vm.expectEmit(true, true, true, false);
        emit ProposalExcuted(data.targetAddress, proposalId, data.encodedData, data.status);

        vm.warp(block.timestamp + 8 days);

        vm.prank(nico);
        daoVoting.executeProposal(proposalId);

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Executed);
    }

    function testExecuteTransactionRevertWhenActionFailed() public {
        MaliciousContract malicious = new MaliciousContract();

        vm.startPrank(proposer);
        daoVoting.submitProposal(address(malicious), "", "reduce fee", votePeriod);

        uint256 proposalId = 1;

        vm.warp(block.timestamp + 1 days);

        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.AbstainFromVote);
        vm.stopPrank();

        vm.prank(voter);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.startPrank(nico);
        daoVoting.castVote(proposalId, DAOVoting.VoteChoice.voteFor);

        vm.warp(block.timestamp + 11 days);

        daoVoting.finalizeVote(proposalId);

        daoVoting.queueProposal(proposalId);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(voter);
        vm.expectRevert();
        daoVoting.executeProposal(proposalId);
    }

    //_____________________
    // CancelProposal
    //_____________________

    function testCancelTransactionRevertWhenProposalIsExcuted() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 12 days);

        vm.startPrank(voter);

        daoVoting.finalizeVote(proposalId);

        daoVoting.queueProposal(proposalId);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.startPrank(nico);
        daoVoting.executeProposal(proposalId);

        vm.expectRevert(DAOVoting.DAOVoting__ProposalIsExecuted.selector);
        daoVoting.cancelProposal(proposalId);
        vm.stopPrank();
    }

    function testCancelProposalUpdateStatusEmitEvent() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.warp(block.timestamp + 12 days);

        vm.startPrank(voter);

        daoVoting.finalizeVote(proposalId);

        daoVoting.queueProposal(proposalId);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        DAOVoting.ProposalData memory data = daoVoting.getProposal(proposalId);

        uint256 proposerBalance = daoVoting.getVoterWeight(proposer, proposalId);

        vm.expectEmit(true, true, false, false);
        emit ProposalCanceled(data.proposer, proposalId, proposerBalance, data.status);

        vm.prank(voter);
        daoVoting.cancelProposal(proposalId);

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Canceled);
    }

    //_____________________
    // State
    //_____________________

    function testStateRevertWhenProposalIdIsInvalid() public {
        uint256 proposalId = 1;

        vm.expectRevert(DAOVoting.DAOVoting__InvalidProposalId.selector);
        vm.prank(voter);
        daoVoting.state(proposalId);
    }

    function testStateIsConsistent() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        vm.prank(proposer);
        daoVoting.state(proposalId);

        assert(daoVoting.getProposal(proposalId).status == DAOVoting.ProposalStatus.Active);
    }

    //_____________________
    // GetProposal
    //_____________________

    function testGetProposalRevertInvalidProposal() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidProposalId.selector);
        daoVoting.getProposal(100);
    }

    function testGetProposalIsConsistent() public proposalSubmitted {
        uint256 proposalId = 1;

        DAOVoting.ProposalData memory data = daoVoting.getProposal(proposalId);

        assert(data.proposer == proposer);
    }

    //_____________________
    // GetReceipts
    //_____________________

    function testGetReceiptsRevertInvalidReceipts() public {
        vm.expectRevert(DAOVoting.DAOVoting__InvalidReceipts.selector);
        daoVoting.getReceipts(nico, 100);
    }

    function testGetReceiptsIsConsistent() public proposalSubmitted forwardTime voteCasted {
        uint256 proposalId = 1;

        DAOVoting.VoteReceipt memory receipts = daoVoting.getReceipts(voter, proposalId);

        assert(receipts.hasVoted == true);
    }
}
