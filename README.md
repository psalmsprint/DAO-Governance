# DAO Governance Voting System

A decentralized autonomous organization (DAO) governance system built with Solidity, featuring weighted voting, snapshot-based vote tracking, and a complete proposal lifecycle.

## Features

- **Weighted Voting**: Vote power based on token holdings
- **Snapshot Mechanism**: Prevents flash loan attacks by using historical balances
- **Complete Proposal Lifecycle**: Submit → Vote → Finalize → Queue → Execute
- **Quorum Requirements**: 75% participation threshold for proposal success
- **Timelock Integration**: Delayed execution for security
- **Comprehensive Test Suite**: Edge cases and attack vector testing

## Architecture

### Core Components

- **DAOVoting.sol**: Main governance contract
- **VotesMock.sol**: ERC20 token with voting capabilities
- **TimeLock**: Delayed execution mechanism
- **DeployDAOVoting.s.sol**: Deployment script

### Proposal States

1. **Pending**: Just created, waiting for vote delay
2. **Active**: Voting in progress
3. **Succeeded**: Passed vote and quorum
4. **Defeated**: Failed to meet requirements
5. **Queued**: Waiting in timelock
6. **Executed**: Successfully executed
7. **Canceled**: Proposer lost minimum tokens

## Security Features

### Flash Loan Protection
Uses snapshot-based voting to prevent attackers from borrowing tokens, voting, and returning them in a single transaction.
```solidity
uint256 weight = token.getPastVotes(voter, snapshotBlock);
```

### Access Control
- Minimum token requirement for proposal submission
- Proposer validation at queue time
- Double voting prevention

### Vote Tallying
Weighted by token holdings, not simple one-person-one-vote:
```solidity
voteTally.totalVoteFor += weight;  // Not just +1
```

## Installation
```bash
# Clone the repository
git clone https://github.com/psalmsprint/DAO-Governance
cd DAO-Governance

# Install dependencies
forge install

# Build
forge build
```

## Usage

### Run Tests
```bash
# Run all tests
make test

# Run with verbose output
make test-v

# Run specific test
forge test --match-test testCastVote -vvvv

# Generate coverage report
make coverage
```

### Deploy
```bash
# Local deployment
make deploy-local

# Testnet deployment
make deploy-sepolia
```

### Environment Setup

Create a `.env` file:
```env
SEPOLIA_RPC_URL=your_rpc_url
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_api_key
```

## Testing

Comprehensive test suite covering:

- ✅ Proposal submission with token requirements
- ✅ Weighted vote casting
- ✅ Quorum calculations
- ✅ Double voting prevention
- ✅ Proposal finalization
- ✅ Queue and execution flow
- ✅ Malicious contract handling
- ✅ Edge cases and attack vectors

## Key Contracts

### DAOVoting
```solidity
// Submit a proposal
function submitProposal(
    address targetAddress,
    bytes calldata action,
    string memory description,
    uint256 votePeriod
) external

// Cast a vote
function castVote(uint256 proposalId, VoteChoice voteChoice) external

// Finalize voting
function finalizeVote(uint256 proposalId) external

// Queue for execution
function queueProposal(uint256 proposalId) external

// Execute proposal
function executeProposal(uint256 proposalId) external
```

## Constants
```solidity
MINIMUM_QUORUM = 7500;        // 75% in basis points
BASIS_POINT = 10000;          // 100%
MIN_PROPOSAL_TOKEN = 1000;    // Minimum tokens to propose
PROPOSAL_DELAY = 1 days;      // Delay before voting starts
```

## Attack Vectors Considered

- ✅ Flash loan voting attacks (prevented via snapshots)
- ✅ Double voting (prevented via vote receipts)
- ✅ Proposer token dump (checked at queue time)
- ✅ Execution failures (handled gracefully)
- ✅ Unauthorized voters (weight validation)

## Makefile Commands
```bash
make build           # Build the project
make test            # Run all tests
make test-v          # Run tests with verbose output
make coverage        # Generate coverage report
make format          # Format Solidity files
make clean           # Clean build artifacts
make deploy-local    # Deploy to local network
make deploy-sepolia  # Deploy to Sepolia testnet
make snapshot        # Create gas snapshot
```

## Project Structure
```
.
├── src/
│   ├── DAOVoting.sol
│   └── VotesMock.sol
├── script/
│   └── DeployDAOVoting.s.sol
├── test/
│   ├── DAOVotingTest.t.sol
│   └── MaliciousContract.sol
├── Makefile
└── README.md
```

## Gas Optimization

- Uses storage efficiently with packed structs
- Caches storage reads in memory
- Minimal external calls

## Known Limitations

- Single proposal execution per transaction
- Fixed quorum percentage (not adjustable)
- Basic timelock implementation

## Future Improvements

- [ ] Adjustable quorum parameters
- [ ] Delegation system
- [ ] Proposal cancellation by proposer
- [ ] Multi-sig execution requirements
- [ ] Gas optimizations

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a PR.

## Security

This is educational code. **DO NOT use in production without a professional audit.**

Found a vulnerability? Please report it responsibly.

## Author

Built as part of learning Solidity security and DAO governance mechanisms.

## Acknowledgments

- OpenZeppelin for secure contract patterns
- Foundry for development framework
- The Ethereum community for security research

---

**⚠️ Educational Purpose Only**: This code has not been audited. Use at your own risk.