// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {Base} from "./Base.t.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IContainerAgent} from "contracts/interfaces/IContainerAgent.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {IMessageRouter} from "contracts/interfaces/IMessageRouter.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {IMessageAdapter} from "contracts/interfaces/IMessageAdapter.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";

import {ContainerAgent} from "contracts/ContainerAgent.sol";
import {Utils} from "./Utils.sol";

import {MockStrategy} from "test/mocks/MockStrategy.sol";

abstract contract L2Base is Base {
    using stdStorage for StdStorage;

    ISwapRouter internal swapRouter;
    IMessageRouter internal messageRouter;
    IBridgeAdapter internal bridgeAdapter;
    IMessageAdapter internal messageAdapter;

    address internal vault;
    IContainerAgent internal containerAgent;

    uint256 internal constant REMOTE_CHAIN_ID = 1;

    function setUp() public virtual override {
        super.setUp();

        vault = makeAddr("VAULT");

        swapRouter = _deploySwapRouter();
        messageRouter = _deployMockMessageRouter(MAX_CACHE_SIZE);
        bridgeAdapter = _deployBridgeAdapter();
        messageAdapter = _deployMessageAdapter();

        vm.startPrank(roles.governance);
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(notion));
        bridgeAdapter.setBridgePath(address(dai), REMOTE_CHAIN_ID, address(dai));
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(this));
        vm.stopPrank();
    }

    function _deployContainerAgent() internal returns (IContainerAgent) {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: address(vault),
            notion: address(notion),
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            swapRouter: address(swapRouter)
        });
        ICrossChainContainer.CrossChainContainerInitParams memory crossChainInitParams = ICrossChainContainer
            .CrossChainContainerInitParams({messageRouter: address(messageRouter), remoteChainId: REMOTE_CHAIN_ID});

        address implementation = address(new ContainerAgent());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                ContainerAgent.initialize.selector,
                containerInitParams,
                crossChainInitParams,
                roles.emergencyManager
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
                token: token,
                amount: amount,
                chainTo: REMOTE_CHAIN_ID,
                minTokenAmount: Utils.calculateMinBridgeAmount(address(containerAgent), amount),
                payload: ""
            });
    }
}
