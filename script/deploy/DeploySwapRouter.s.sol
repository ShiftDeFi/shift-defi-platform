// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SwapRouter} from "contracts/SwapRouter.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeploySwapRouter is RolesRegistry, DeploySaltedProxy {
    function run() public {
        _loadRoles();

        bytes memory data = abi.encodeWithSelector(
            SwapRouter.initialize.selector,
            roles.defaultAdmin,
            roles.whitelistManager
        );

        vm.startBroadcast();
        address implementation = address(new SwapRouter());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
