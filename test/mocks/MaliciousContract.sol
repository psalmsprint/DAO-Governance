// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

contract MaliciousContract {
    error ExecutionReverted();
    error DAOVoting__ExcutionFailed();

    function alwaysReverts() external pure {
        revert ExecutionReverted();
    }

    receive() external payable {
        revert DAOVoting__ExcutionFailed();
    }
}
