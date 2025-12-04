// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TimeLock {
    uint256 public immutable delay;

    mapping(bytes32 => bool) public queued;

    event Queued(bytes32 indexed txId);
    event Executed(bytes32 indexed txId);
    event Cancelled(bytes32 indexed txId);

    constructor(uint256 _delay) {
        delay = _delay;
    }

    receive() external payable {}

    function getTxId(address target, uint256 value, bytes calldata data, uint256 timestamp)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(target, value, data, timestamp));
    }

    function queue(address target, uint256 value, bytes calldata data, uint256 timestamp)
        external
        returns (bytes32 txId)
    {
        require(timestamp >= block.timestamp + delay, "Timestamp < delay");

        txId = getTxId(target, value, data, timestamp);
        queued[txId] = true;

        emit Queued(txId);
    }

    function execute(address target, uint256 value, bytes calldata data, uint256 timestamp)
        external
        payable
        returns (bytes memory)
    {
        bytes32 txId = getTxId(target, value, data, timestamp);
        require(queued[txId], "Not queued");
        require(block.timestamp >= timestamp, "Too early");
        require(block.timestamp <= timestamp + 2 hours, "Expired");

        queued[txId] = false;

        (bool ok, bytes memory res) = target.call{value: value}(data);
        require(ok, "Execution failed");

        emit Executed(txId);
        return res;
    }

    function cancel(address target, uint256 value, bytes calldata data, uint256 timestamp) external {
        bytes32 txId = getTxId(target, value, data, timestamp);
        require(queued[txId], "Not queued");

        queued[txId] = false;
        emit Cancelled(txId);
    }
}
