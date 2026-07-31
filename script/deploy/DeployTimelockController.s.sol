// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployTimelockController is Script {
    address public defaultAdmin = vm.envAddress("TIMELOCK_DEFAULT_ADMIN_ROLE");
    address public proposer = vm.envAddress("PROPOSER_ROLE");
    address public executor = vm.envAddress("EXECUTOR_ROLE");
    uint256 public minDelay = vm.envUint("MIN_TIMELOCK_DELAY");

    function run() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        vm.startBroadcast();
        new TimelockController(minDelay, proposers, executors, defaultAdmin);
        vm.stopBroadcast();
    }
}
