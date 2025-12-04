//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {VotesMock} from "../test/mocks/VotesMock.sol";
import {TimeLock} from "../test/mocks/TimeLock.sol";
import {DAOVoting} from "../src/DAOVoting.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address token;
        address timeLockContract;
        uint256 minVotingPeriod;
        uint256 timeLockDelay;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetETHConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvil();
        }
    }

    function getSepoliaConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();

        VotesMock voteMocks = new VotesMock();
        TimeLock timeLock = new TimeLock(2 days);

        vm.stopBroadcast();

        NetworkConfig memory sepoliaConfig = NetworkConfig({
            token: address(voteMocks),
            timeLockContract: address(timeLock),
            minVotingPeriod: 7 days,
            timeLockDelay: 2 days
        });

        return sepoliaConfig;
    }

    function getMainnetETHConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();

        VotesMock voteMocks = new VotesMock();
        TimeLock timeLock = new TimeLock(2 days);

        vm.stopBroadcast();

        NetworkConfig memory mainnetETHConfig = NetworkConfig({
            token: address(voteMocks),
            timeLockContract: address(timeLock),
            minVotingPeriod: 7 days,
            timeLockDelay: 2 days
        });

        return mainnetETHConfig;
    }

    function getOrCreateAnvil() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.token != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        VotesMock voteMocks = new VotesMock();
        TimeLock timeLock = new TimeLock(2 days);

        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            token: address(voteMocks),
            timeLockContract: address(timeLock),
            minVotingPeriod: 7 days,
            timeLockDelay: 2 days
        });

        return anvilConfig;
    }
}
