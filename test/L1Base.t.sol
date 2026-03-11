// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {Base} from "./Base.t.sol";
import {MockContainerPrincipal} from "test/mocks/MockContainerPrincipal.sol";
import {MockBridgeAdapter} from "test/mocks/MockBridgeAdapter.sol";
import {MockContainerLocal} from "test/mocks/MockContainerLocal.sol";
import {ContainerLocal} from "contracts/ContainerLocal.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {PriceOracleAggregator} from "contracts/PriceOracleAggregator.sol";
import {MockCrossChainContainer} from "test/mocks/MockCrossChainContainer.sol";

import {Vault} from "contracts/Vault.sol";
import {ContainerPrincipal} from "contracts/ContainerPrincipal.sol";
import {SwapRouter} from "contracts/SwapRouter.sol";
import {ReshufflingGateway} from "contracts/ReshufflingGateway.sol";
import {Utils} from "./Utils.sol";

import {IVault} from "contracts/interfaces/IVault.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {IMessageRouter} from "contracts/interfaces/IMessageRouter.sol";
import {IMessageAdapter} from "contracts/interfaces/IMessageAdapter.sol";
import {ISwapAdapter} from "contracts/interfaces/ISwapAdapter.sol";
import {IPriceOracleAggregator} from "contracts/interfaces/IPriceOracleAggregator.sol";
import {IReshufflingGateway} from "contracts/interfaces/IReshufflingGateway.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";

abstract contract L1Base is Base {
    using SafeERC20 for MockERC20;
    using stdStorage for StdStorage;

    IVault internal vault;
    IContainerPrincipal internal containerPrincipal;

    ISwapRouter internal swapRouter;
    ISwapAdapter internal mockSwapAdapter;
    IMessageRouter internal messageRouter;
    MockBridgeAdapter internal bridgeAdapter;
    IMessageAdapter internal messageAdapter;
    IReshufflingGateway internal reshufflingGateway;

    uint256 internal constant REMOTE_CHAIN_ID = 42161;

    uint256 internal constant MAX_DEPOSIT_AMOUNT = 100_000;
    uint256 internal constant MIN_DEPOSIT_AMOUNT = 10_000;
    uint256 internal constant MAX_DEPOSIT_BATCH_SIZE = 1_000_000;
    uint256 internal constant MIN_DEPOSIT_BATCH_SIZE = 10_000;
    uint256 internal constant MIN_WITHDRAW_BATCH_RATIO = 0.01e18; // 1%
    uint256 internal constant FORCED_DEPOSIT_THRESHOLD = 1_000 * NOTION_PRECISION;
    uint256 internal constant FORCED_WITHDRAW_THRESHOLD = 1_000e18;
    uint256 internal constant FORCED_BATCH_BLOCK_LIMIT = 100_000;

    uint256 internal constant DEPOSIT_AMOUNT = 10_000 * NOTION_PRECISION;
    uint256 internal constant WITHDRAW_SHARES_AMOUNT = 10_000 * NOTION_PRECISION;

    uint256 internal constant MIN_SHARES_AMOUNT = 1e18;
    uint256 internal constant MAX_SHARES_AMOUNT = 10_000_000 * 1e18;

    uint256 internal constant MIN_TOKEN_AMOUNT = 1e6;
    uint256 internal constant MAX_TOKEN_AMOUNT = 10_000_000 * 1e18;

    function setUp() public virtual override {
        super.setUp();
        vault = _deployVault();
        vm.label(address(vault), "VAULT");

        vm.startPrank(roles.defaultAdmin);
        AccessControl(address(vault)).grantRole(CONTAINER_MANAGER_ROLE, roles.containerManager);
        AccessControl(address(vault)).grantRole(OPERATOR_ROLE, roles.operator);
        AccessControl(address(vault)).grantRole(CONFIGURATOR_ROLE, roles.configurator);
        AccessControl(address(vault)).grantRole(EMERGENCY_MANAGER_ROLE, roles.emergencyManager);
        AccessControl(address(vault)).grantRole(TOKEN_MANAGER_ROLE, roles.tokenManager);
        vm.stopPrank();

        swapRouter = _deploySwapRouter();
        messageRouter = _deployMockMessageRouter(MAX_CACHE_SIZE);
        bridgeAdapter = _deployBridgeAdapter();
        messageAdapter = _deployMessageAdapter();
        mockSwapAdapter = _deployMockSwapAdapter();

        deal(address(dai), address(this), 100_000_000e18);
        deal(address(dai), address(mockSwapAdapter), 100_000_000e18);
        deal(address(notion), address(this), 100_000_000e18);
        deal(address(notion), address(mockSwapAdapter), 100_000_000e18);
        reshufflingGateway = _deployReshufflingGateway();

        vm.prank(roles.governance);
        bridgeAdapter.setSlippageCapPct(MAX_BPS);

        vm.startPrank(roles.defaultAdmin);
        AccessControl(address(swapRouter)).grantRole(WHITELIST_MANAGER_ROLE, roles.whitelistManager);
        AccessControl(address(reshufflingGateway)).grantRole(WHITELIST_MANAGER_ROLE, roles.whitelistManager);
        AccessControl(address(reshufflingGateway)).grantRole(RESHUFFLING_MANAGER_ROLE, roles.reshufflingManager);
        vm.stopPrank();
    }

    function _deployVault() internal returns (IVault) {
        address implementation = address(new Vault());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                Vault.initialize.selector,
                "Vault",
                "VAULT",
                address(notion),
                IVault.RoleAddresses({
                    defaultAdmin: roles.defaultAdmin,
                    containerManager: roles.containerManager,
                    operator: roles.operator,
                    configurator: roles.configurator,
                    emergencyManager: roles.emergencyManager
                }),
                IVault.Limits({
                    maxDepositAmount: MAX_DEPOSIT_AMOUNT * NOTION_PRECISION,
                    minDepositAmount: MIN_DEPOSIT_AMOUNT * NOTION_PRECISION,
                    maxDepositBatchSize: MAX_DEPOSIT_BATCH_SIZE * NOTION_PRECISION,
                    minDepositBatchSize: MIN_DEPOSIT_BATCH_SIZE * NOTION_PRECISION,
                    minWithdrawBatchRatio: MIN_WITHDRAW_BATCH_RATIO
                }),
                FORCED_DEPOSIT_THRESHOLD,
                FORCED_WITHDRAW_THRESHOLD,
                FORCED_BATCH_BLOCK_LIMIT
            )
        );
        return IVault(proxy);
    }

    function _setVaultStatus(IVault.VaultStatus status) internal {
        stdstore.target(address(vault)).sig(vault.status.selector).checked_write(uint256(status));
    }

    function _deployMockContainerPrincipal() internal returns (IContainerPrincipal) {
        return new MockContainerPrincipal(address(vault), address(notion), REMOTE_CHAIN_ID);
    }

    function _deployMockContainerLocal() internal returns (IContainerLocal) {
        return new MockContainerLocal();
    }

    function _deployContainerPrincipal() internal returns (IContainerPrincipal) {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: address(vault),
            notion: address(notion),
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            swapRouter: address(swapRouter)
        });

        ICrossChainContainer.CrossChainContainerInitParams memory crossChainInitParams = ICrossChainContainer
            .CrossChainContainerInitParams({messageRouter: address(messageRouter), remoteChainId: REMOTE_CHAIN_ID});

        address implementation = address(new ContainerPrincipal());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(ContainerPrincipal.initialize.selector, containerInitParams, crossChainInitParams)
        );
        return IContainerPrincipal(proxy);
    }

    function _deploySwapRouter() internal override returns (ISwapRouter) {
        address implementation = address(new SwapRouter());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(SwapRouter.initialize.selector, roles.defaultAdmin)
        );
        return ISwapRouter(proxy);
    }

    function _deployContainerLocal() internal returns (IContainerLocal) {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: address(vault),
            notion: address(notion),
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            swapRouter: address(swapRouter)
        });

        address implementation = address(new ContainerLocal());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(ContainerLocal.initialize.selector, containerInitParams)
        );
        return IContainerLocal(proxy);
    }

    function _deployMockCrossChainContainer() internal returns (MockCrossChainContainer) {
        address implementation = address(new MockCrossChainContainer());
        return
            MockCrossChainContainer(
                _proxify(
                    roles.deployer,
                    implementation,
                    roles.defaultAdmin,
                    abi.encodeWithSelector(
                        MockCrossChainContainer.initialize.selector,
                        IContainer.ContainerInitParams({
                            vault: address(vault),
                            notion: address(notion),
                            defaultAdmin: roles.defaultAdmin,
                            operator: roles.operator,
                            swapRouter: address(swapRouter)
                        }),
                        ICrossChainContainer.CrossChainContainerInitParams({
                            messageRouter: address(messageRouter),
                            remoteChainId: REMOTE_CHAIN_ID
                        })
                    )
                )
            );
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
                address(notion),
                address(swapRouter),
                roles.defaultAdmin
            )
        );
        return IReshufflingGateway(proxy);
    }

    function _deployPriceOracleAggregator() internal returns (IPriceOracleAggregator) {
        address implementation = address(new PriceOracleAggregator());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(PriceOracleAggregator.initialize.selector, roles.defaultAdmin, roles.oracleManager)
        );
        return IPriceOracleAggregator(proxy);
    }

    function _addContainer(address container, uint256 chainId) internal {
        vm.prank(roles.containerManager);
        vault.addContainer(container, chainId);
    }

    function _whitelistToken(address container, address token) internal {
        vm.prank(roles.tokenManager);
        IContainer(container).whitelistToken(token);
    }

    function _deposit(address user, uint256 amount) internal {
        notion.mint(user, amount);

        vm.startPrank(user);
        notion.safeIncreaseAllowance(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _setContainerLocalStatus(
        IContainerLocal containerLocal_,
        IContainerLocal.ContainerLocalStatus status
    ) internal {
        stdstore.target(address(containerLocal_)).sig(containerLocal_.status.selector).checked_write(uint256(status));
    }

    function _setContainerPrincipalStatus(
        IContainerPrincipal containerPrincipal_,
        IContainerPrincipal.ContainerPrincipalStatus status
    ) internal {
        stdstore.target(address(containerPrincipal_)).sig(containerPrincipal_.status.selector).checked_write(
            uint256(status)
        );
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
                minTokenAmount: Utils.calculateMinBridgeAmount(address(containerPrincipal), amount),
                payload: ""
            });
    }

    /// @dev Sorts containers and weights in place by container address (strict ascending) for setContainerWeights.
    function _sortContainersAndWeights(address[] memory containers, uint256[] memory weights) internal pure {
        uint256 n = containers.length;
        for (uint256 i = 1; i < n; ++i) {
            address keyAddr = containers[i];
            uint256 keyWeight = weights[i];
            uint256 j = i;
            while (j > 0 && containers[j - 1] > keyAddr) {
                containers[j] = containers[j - 1];
                weights[j] = weights[j - 1];
                --j;
            }
            containers[j] = keyAddr;
            weights[j] = keyWeight;
        }
    }
}
