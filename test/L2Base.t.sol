// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ContainerAgent} from "contracts/ContainerAgent.sol";
import {ReshufflingGateway} from "contracts/ReshufflingGateway.sol";

import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IMessageAdapter} from "contracts/interfaces/IMessageAdapter.sol";
import {IMessageRouter} from "contracts/interfaces/IMessageRouter.sol";
import {IReshufflingGateway} from "contracts/interfaces/IReshufflingGateway.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";

import {Base} from "./Base.t.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {Utils} from "./Utils.sol";

abstract contract L2Base is Base {
    using stdStorage for StdStorage;

    ISwapRouter internal swapRouter;
    IMessageRouter internal messageRouter;
    IBridgeAdapter internal bridgeAdapter;
    IMessageAdapter internal messageAdapter;
    IReshufflingGateway internal reshufflingGateway;

    address internal vault;
    IContainerAgent internal containerAgent;

    uint256 internal constant REMOTE_CHAIN_ID = 1;

    function setUp() public virtual override {
        super.setUp();

        vault = makeAddr("VAULT");

        swapRouter = _deployMockSwapRouter();
        messageRouter = _deployMockMessageRouter(MAX_CACHE_SIZE);
        bridgeAdapter = _deployBridgeAdapter();
        messageAdapter = _deployMessageAdapter();
        reshufflingGateway = _deployReshufflingGateway();

        vm.startPrank(roles.bridgeAdapterManager);
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(notion));
        bridgeAdapter.setBridgePath(address(dai), REMOTE_CHAIN_ID, address(dai));
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(this));
        vm.stopPrank();
    }

    function _deployReshufflingGateway() internal returns (IReshufflingGateway) {
        address implementation = address(new ReshufflingGateway());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                ReshufflingGateway.initialize.selector,
                address(vault),
                address(swapRouter),
                roles.defaultAdmin,
                roles.bridgeAdapterManager,
                roles.reshufflingExecutor,
                roles.tokenManager,
                roles.emergencyPauser
            )
        );
        vm.label(address(proxy), "RESHUFFLING_GATEWAY");
        return IReshufflingGateway(proxy);
    }

    function _deployContainerAgent() internal returns (IContainerAgent) {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: address(vault),
            notion: address(notion),
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            emergencyPauser: roles.emergencyPauser,
            tokenManager: roles.tokenManager,
            swapRouter: address(swapRouter)
        });

        address implementation = address(new ContainerAgent());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                ContainerAgent.initialize.selector,
                containerInitParams,
                ICrossChainContainer.CrossChainContainerInitParams({
                    messageRouter: address(messageRouter),
                    remoteChainId: REMOTE_CHAIN_ID,
                    messengerManager: roles.messengerManager,
                    bridgeAdapterManager: roles.bridgeAdapterManager
                }),
                IStrategyContainer.StrategyContainerInitParams({
                    roleAddresses: IStrategyContainer.RoleAddresses({
                        strategyManager: roles.strategyManager,
                        harvestManager: roles.harvestManager,
                        reshufflingManager: roles.reshufflingManager,
                        reshufflingExecutor: roles.reshufflingExecutor,
                        emergencyManager: roles.emergencyManager,
                        emergencyExecutor: roles.emergencyExecutor
                    }),
                    reshufflingGateway: address(reshufflingGateway),
                    treasury: treasury,
                    feePct: DEFAULT_FEE_PCT,
                    priceOracle: address(priceOracleAggregator)
                })
            )
        );

        vm.label(proxy, "CONTAINER_AGENT");

        return IContainerAgent(proxy);
    }

    function _deployMockStrategy() internal returns (IStrategyTemplate) {
        address implementation = address(new MockStrategy());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(MockStrategy.initialize.selector, address(containerAgent))
        );
        vm.label(proxy, "MOCK_STRATEGY");
        return IStrategyTemplate(proxy);
    }

    function _setContainerAgentStatus(IContainerAgent.ContainerAgentStatus status) internal {
        stdstore.target(address(containerAgent)).sig(IContainerAgent.status.selector).checked_write(uint256(status));
    }

    function _craftBridgeInstruction(
        address token,
        uint256 amount
    ) internal view returns (IBridgeAdapter.BridgeInstruction memory) {
        return
            IBridgeAdapter.BridgeInstruction({
                value: 0,
                token: token,
                amount: amount,
                chainTo: REMOTE_CHAIN_ID,
                minTokenAmount: Utils.calculateMinBridgeAmount(amount),
                payload: ""
            });
    }
}
