// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

abstract contract RolesRegistry {
    struct Roles {
        address proxyAdminOwner;
        address defaultAdmin;
        address containerManager;
        address operator;
        address configurator;
        address reshufflingManager;
        address reshufflingExecutor;
        address emergencyPauser;
        address whitelistManager;
        address oracleManager;
        address tokenManager;
        address bridgeAdapterManager;
        address emergencyManager;
        address emergencyExecutor;
        address strategyManager;
        address harvestManager;
    }

    Roles roles;

    function _loadRoles() internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        roles = Roles({
            proxyAdminOwner: vm.envAddress("PROXY_ADMIN_OWNER"),
            defaultAdmin: vm.envAddress("DEFAULT_ADMIN_ROLE"),
            containerManager: vm.envAddress("CONTAINER_MANAGER_ROLE"),
            operator: vm.envAddress("OPERATOR_ROLE"),
            configurator: vm.envAddress("CONFIGURATOR_ROLE"),
            reshufflingManager: vm.envAddress("RESHUFFLING_MANAGER_ROLE"),
            reshufflingExecutor: vm.envAddress("RESHUFFLING_EXECUTOR_ROLE"),
            emergencyPauser: vm.envAddress("EMERGENCY_PAUSER_ROLE"),
            whitelistManager: vm.envAddress("WHITELIST_MANAGER_ROLE"),
            oracleManager: vm.envAddress("ORACLE_MANAGER_ROLE"),
            tokenManager: vm.envAddress("TOKEN_MANAGER_ROLE"),
            bridgeAdapterManager: vm.envAddress("BRIDGE_ADAPTER_MANAGER_ROLE"),
            emergencyManager: vm.envAddress("EMERGENCY_MANAGER_ROLE"),
            emergencyExecutor: vm.envAddress("EMERGENCY_EXECUTOR_ROLE"),
            strategyManager: vm.envAddress("STRATEGY_MANAGER_ROLE"),
            harvestManager: vm.envAddress("HARVEST_MANAGER_ROLE")
        });
    }
}
