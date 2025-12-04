// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DAOVoting} from "../src/DAOVoting.sol";

contract DeployDAOVoting is Script {
    function run() external returns (DAOVoting, HelperConfig) {
        HelperConfig helper = new HelperConfig();

        (address token, address timeLockContract, uint256 minVotingPeriod, uint256 timeLockDelay) =
            helper.activeNetworkConfig();

        vm.startBroadcast();

        DAOVoting daoVoting = new DAOVoting(token, timeLockContract, minVotingPeriod, timeLockDelay);

        vm.stopBroadcast();

        return (daoVoting, helper);
    }
}
