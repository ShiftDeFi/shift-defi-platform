// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

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
        (, address deployer, ) = vm.readCallers();

        // The deployer takes DEFAULT_ADMIN_ROLE temporarily so it can reshuffle the roles the
        // constructor hardcodes, then hands the role over to the multisig below.
        TimelockController timelock = new TimelockController(minDelay, proposers, executors, deployer);

        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        // The constructor grants CANCELLER_ROLE to proposer; move it to the executor instead.
        timelock.revokeRole(cancellerRole, proposer);
        timelock.grantRole(cancellerRole, executor);

        timelock.grantRole(adminRole, defaultAdmin);
        if (deployer != defaultAdmin) {
            timelock.renounceRole(adminRole, deployer);
        }
        vm.stopBroadcast();

        require(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer), "proposer role not set");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), executor), "executor role not set");
        require(timelock.hasRole(cancellerRole, executor), "canceller role not moved to executor");
        require(!timelock.hasRole(cancellerRole, proposer), "canceller role still held by proposer");
        require(timelock.hasRole(adminRole, defaultAdmin), "admin role not handed over");
        require(deployer == defaultAdmin || !timelock.hasRole(adminRole, deployer), "deployer still admin");
    }
}
