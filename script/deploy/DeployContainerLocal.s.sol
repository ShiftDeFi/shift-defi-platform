// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ContainerLocal} from "contracts/ContainerLocal.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployContainerLocal is RolesRegistry, DeploySaltedProxy {
    address public vaultAddress = vm.envAddress("VAULT_ADDRESS");
    address public notionAddress = vm.envAddress("NOTION_TOKEN_ADDRESS");
    address public swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");

    address public reshufflingGatewayAddress = vm.envAddress("RESHUFFLING_GATEWAY_ADDRESS");
    address public treasury = vm.envAddress("TREASURY_ADDRESS");
    uint256 public feePct = vm.envUint("FEE_PCT");
    address public priceOracleAddress = vm.envAddress("PRICE_ORACLE_ADDRESS");

    function run() public {
        _loadRoles();

        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams(
            vaultAddress,
            notionAddress,
            roles.defaultAdmin,
            roles.operator,
            roles.emergencyPauser,
            roles.tokenManager,
            swapRouterAddress
        );

        IStrategyContainer.StrategyContainerInitParams memory strategyContainerInitParams = IStrategyContainer
            .StrategyContainerInitParams(
                IStrategyContainer.RoleAddresses(
                    roles.strategyManager,
                    roles.harvestManager,
                    roles.reshufflingManager,
                    roles.reshufflingExecutor,
                    roles.emergencyManager,
                    roles.emergencyExecutor
                ),
                reshufflingGatewayAddress,
                treasury,
                feePct,
                priceOracleAddress
            );

        bytes memory data = abi.encodeWithSelector(
            ContainerLocal.initialize.selector,
            containerInitParams,
            strategyContainerInitParams
        );

        vm.startBroadcast();
        address implementation = address(new ContainerLocal());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
