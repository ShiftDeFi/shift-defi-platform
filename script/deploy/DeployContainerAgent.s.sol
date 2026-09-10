// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ContainerAgent} from "contracts/ContainerAgent.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployContainerAgent is RolesRegistry, DeploySaltedProxy {
    address public vaultAddress = vm.envAddress("VAULT_ADDRESS");
    address public notionAddress = vm.envAddress("NOTION_TOKEN_ADDRESS");
    address public swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");

    address public messageRouterAddress = vm.envAddress("MESSAGE_ROUTER_ADDRESS");
    uint256 public remoteChainId = vm.envUint("REMOTE_CHAIN_ID");

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

        ICrossChainContainer.CrossChainContainerInitParams memory crossChainContainerInitParams = ICrossChainContainer
            .CrossChainContainerInitParams(
                messageRouterAddress,
                remoteChainId,
                roles.messengerManager,
                roles.bridgeAdapterManager
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
            ContainerAgent.initialize.selector,
            containerInitParams,
            crossChainContainerInitParams,
            strategyContainerInitParams
        );

        vm.startBroadcast();
        address implementation = address(new ContainerAgent());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
