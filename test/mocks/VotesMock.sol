// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract VotesMock is Votes {
    mapping(address voter => uint256) private _votingUnits;

    constructor() EIP712("VotesMock", "1") {}

    function getTotalSupply() public view returns (uint256) {
        return _getTotalSupply();
    }

    function delegate(address account, address newDelegation) public {
        return _delegate(account, newDelegation);
    }

    function _getVotingUnits(address account) internal view override returns (uint256) {
        return _votingUnits[account];
    }

    function mint(address account, uint256 votes) external {
        _mint(account, votes);
    }

    function _mint(address account, uint256 votes) internal {
        _votingUnits[account] += votes;
        _transferVotingUnits(address(0), account, votes);
    }

    // External function to burn for testing
    function burn(address account, uint256 votes) external {
        _burn(account, votes);
    }

    function _burn(address account, uint256 votes) internal {
        _votingUnits[account] -= votes;
        _transferVotingUnits(account, address(0), votes);
    }
}
