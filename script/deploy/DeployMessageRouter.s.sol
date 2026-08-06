// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MessageRouter} from "contracts/MessageRouter.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployMessageRouter is RolesRegistry, DeploySaltedProxy {
    uint256 public maxCacheSize = vm.envUint("MAX_CACHE_SIZE");

    function run() public {
        _loadRoles();

        bytes memory data = abi.encodeWithSelector(
            MessageRouter.initialize.selector,
            roles.defaultAdmin,
            roles.whitelistManager,
            roles.cacheManager,
            maxCacheSize
        );

        vm.startBroadcast();
        address implementation = address(new MessageRouter());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
