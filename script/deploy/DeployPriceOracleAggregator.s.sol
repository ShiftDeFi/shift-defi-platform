// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PriceOracleAggregator} from "contracts/PriceOracleAggregator.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployPriceOracleAggregator is RolesRegistry, DeploySaltedProxy {
    function run() public {
        _loadRoles();

        bytes memory data = abi.encodeWithSelector(
            PriceOracleAggregator.initialize.selector,
            roles.defaultAdmin,
            roles.oracleManager
        );

        vm.startBroadcast();
        address implementation = address(new PriceOracleAggregator());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
