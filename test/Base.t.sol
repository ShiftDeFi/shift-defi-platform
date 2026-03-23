// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PriceOracleAggregator} from "contracts/PriceOracleAggregator.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {IMessageAdapter} from "contracts/interfaces/IMessageAdapter.sol";
import {IMessageRouter} from "contracts/interfaces/IMessageRouter.sol";
import {IPriceOracleAggregator} from "contracts/interfaces/IPriceOracleAggregator.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {ISwapAdapter} from "contracts/interfaces/ISwapAdapter.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";

import {Codec} from "contracts/libraries/Codec.sol";

import {Test} from "forge-std/Test.sol";
import {MockBridgeAdapter} from "./mocks/MockBridgeAdapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMessageAdapter} from "./mocks/MockMessageAdapter.sol";
import {MockMessageRouter} from "./mocks/MockMessageRouter.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockStrategyContainer} from "test/mocks/MockStrategyContainer.sol";
import {MockSwapAdapter} from "./mocks/MockSwapAdapter.sol";
import {MockSwapRouter} from "./mocks/MockSwapRouter.sol";

abstract contract Base is Test {
    using Math for uint256;

    struct Roles {
        address deployer;
        address defaultAdmin;
        address containerManager;
        address operator;
        address configurator;
        address cacheManager;
        address emergencyManager;
        address tokenManager;
        address messengerManager;
        address bridgeAdapterManager;
        address messageAdapterManager;
        address whitelistManager;
        address oracleManager;
        address strategyManager;
        address reshufflingManager;
        address reshufflingExecutor;
        address feederRole;
        address harvestManager;
    }

    struct Users {
        address alice;
        uint256 alicePrivateKey;
        address bob;
        address charlie;
        address david;
        address eve;
    }

    MockERC20 internal notion;
    MockERC20 internal dai;
    IPriceOracleAggregator internal priceOracleAggregator;
    Roles internal roles;
    Users internal users;
    address internal treasury;

    uint256 internal constant MAX_BPS = 1e18;
    uint256 internal constant MAX_SLIPPAGE_CAP_PCT = 1e18;

    uint256 internal constant TOTAL_CONTAINER_WEIGHT = 10_000;

    uint8 internal constant NOTION_DECIMALS = 6;
    uint8 internal constant DAI_DECIMALS = 18;
    uint256 internal constant NOTION_PRECISION = 10 ** NOTION_DECIMALS;
    uint256 internal constant DAI_PRECISION = 10 ** DAI_DECIMALS;
    uint256 internal constant MAX_NOTION_AMOUNT = type(uint256).max / NOTION_PRECISION;
    uint256 internal constant MAX_CACHE_SIZE = 8;
    uint256 internal constant DEFAULT_SLIPPAGE_CAP_PCT = 0.95e18;
    uint256 internal constant DEFAULT_FEE_PCT = 0.01e18;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = "0x00";
    bytes32 internal constant CONTAINER_MANAGER_ROLE = keccak256("CONTAINER_MANAGER_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 internal constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 internal constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 internal constant MESSENGER_MANAGER_ROLE = keccak256("MESSENGER_MANAGER_ROLE");
    bytes32 internal constant BRIDGE_ADAPTER_MANAGER_ROLE = keccak256("BRIDGE_ADAPTER_MANAGER_ROLE");
    bytes32 internal constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");
    bytes32 internal constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 internal constant RESHUFFLING_MANAGER_ROLE = keccak256("RESHUFFLING_MANAGER_ROLE");
    bytes32 internal constant CACHE_MANAGER_ROLE = keccak256("CACHE_MANAGER_ROLE");
    bytes32 internal constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    function setUp() public virtual {
        roles.deployer = makeAddr("DEPLOYER");
        roles.defaultAdmin = makeAddr("DEFAULT_ADMIN");
        roles.containerManager = makeAddr("CONTAINER_MANAGER");
        roles.operator = makeAddr("OPERATOR");
        roles.configurator = makeAddr("CONFIGURATOR");
        roles.cacheManager = makeAddr("CACHE_MANAGER");
        roles.emergencyManager = makeAddr("EMERGENCY_MANAGER");
        roles.tokenManager = makeAddr("TOKEN_MANAGER");
        roles.messengerManager = makeAddr("MESSENGER_MANAGER");
        roles.bridgeAdapterManager = makeAddr("BRIDGE_ADAPTER_MANAGER");
        roles.whitelistManager = makeAddr("WHITELIST_MANAGER");
        roles.oracleManager = makeAddr("ORACLE_MANAGER");
        roles.strategyManager = makeAddr("STRATEGY_MANAGER");
        roles.reshufflingManager = makeAddr("RESHUFFLING_MANAGER");
        roles.reshufflingExecutor = makeAddr("RESHUFFLING_EXECUTOR");
        roles.feederRole = makeAddr("FEEDER_ROLE");
        roles.harvestManager = makeAddr("HARVEST_MANAGER");

        (address alice, uint256 alicePrivateKey) = makeAddrAndKey("ALICE");
        users.alice = alice;
        users.alicePrivateKey = alicePrivateKey;
        users.bob = makeAddr("BOB");
        users.charlie = makeAddr("CHARLIE");
        users.david = makeAddr("DAVID");
        users.eve = makeAddr("EVE");

        notion = _deployMockERC20("Notion", "NTN", NOTION_DECIMALS);
        vm.label(address(notion), "NOTION");
        dai = _deployMockERC20("Dai", "DAI", DAI_DECIMALS);
        vm.label(address(dai), "DAI");
        treasury = makeAddr("TREASURY");
        priceOracleAggregator = _deployPriceOracleAggregator();
    }

    function _proxify(
        address deployer,
        address implementation,
        address proxyAdminOwner,
        bytes memory data
    ) internal returns (address) {
        vm.prank(deployer);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, proxyAdminOwner, data);
        return address(proxy);
    }

    function _deployMockERC20(string memory name, string memory symbol, uint8 decimals) internal returns (MockERC20) {
        return new MockERC20(name, symbol, decimals);
    }

    function _deployMockSwapRouter() internal returns (ISwapRouter) {
        return new MockSwapRouter();
    }

    function _deployMockMessageRouter(uint256 maxCacheSize) internal returns (IMessageRouter) {
        return new MockMessageRouter(maxCacheSize);
    }

    function _deployBridgeAdapter() internal returns (MockBridgeAdapter) {
        address implementation = address(new MockBridgeAdapter());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                MockBridgeAdapter.initialize.selector,
                roles.defaultAdmin,
                roles.bridgeAdapterManager,
                DEFAULT_SLIPPAGE_CAP_PCT
            )
        );
        return MockBridgeAdapter(payable(proxy));
    }

    function _deployMessageAdapter() internal returns (IMessageAdapter) {
        return new MockMessageAdapter();
    }

    function _deployMockSwapAdapter() internal returns (ISwapAdapter) {
        return new MockSwapAdapter();
    }

    function _deployMockStrategyContainer() internal returns (MockStrategyContainer) {
        IContainer.ContainerInitParams memory containerInitParams = IContainer.ContainerInitParams({
            vault: makeAddr("VAULT"),
            notion: address(notion),
            defaultAdmin: roles.defaultAdmin,
            operator: roles.operator,
            tokenManager: roles.tokenManager,
            swapRouter: makeAddr("SWAP_ROUTER")
        });

        address implementation = address(new MockStrategyContainer());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                MockStrategyContainer.initialize.selector,
                containerInitParams,
                IStrategyContainer.RoleAddresses({
                    strategyManager: roles.strategyManager,
                    harvestManager: roles.harvestManager,
                    reshufflingManager: roles.reshufflingManager,
                    emergencyManager: roles.emergencyManager
                }),
                makeAddr("RESHUFFLING_GATEWAY"),
                treasury,
                DEFAULT_FEE_PCT,
                address(priceOracleAggregator)
            )
        );

        vm.label(proxy, "MOCK_STRATEGY_CONTAINER");

        return MockStrategyContainer(proxy);
    }

    function _deployMockStrategy(address strategyContainer) internal returns (MockStrategy) {
        address implementation = address(new MockStrategy());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(MockStrategy.initialize.selector, strategyContainer)
        );
        vm.label(proxy, "MOCK_STRATEGY");
        return MockStrategy(proxy);
    }

    function _deployPriceOracleAggregator() internal returns (IPriceOracleAggregator) {
        address implementation = address(new PriceOracleAggregator());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(PriceOracleAggregator.initialize.selector, roles.defaultAdmin, roles.oracleManager)
        );
        vm.label(address(proxy), "PRICE_ORACLE_AGGREGATOR");
        return IPriceOracleAggregator(proxy);
    }

    function _getAddressUintMappingValue(
        address targetContract,
        uint256 mapSlot,
        address key
    ) internal view returns (uint256) {
        bytes32 slotValue = vm.load(targetContract, keccak256(abi.encode(key, mapSlot)));
        return uint256(slotValue);
    }

    function _craftSwapInstruction(
        address _adapter,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bytes memory _payload
    ) internal pure returns (ISwapRouter.SwapInstruction memory) {
        return
            ISwapRouter.SwapInstruction({
                adapter: _adapter,
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                amountIn: _amountIn,
                minAmountOut: _minAmountOut,
                payload: _payload
            });
    }

    function _craftDepositRequestMessage(
        address[] memory tokens,
        uint256[] memory amounts
    ) internal pure returns (bytes memory) {
        Codec.DepositRequest memory request = Codec.DepositRequest({tokens: tokens, amounts: amounts});
        return Codec.encode(request);
    }

    function _craftWithdrawalRequestMessage(uint256 share) internal pure returns (bytes memory) {
        return Codec.encode(Codec.WithdrawalRequest({share: share}));
    }

    function _createRandomTokensArray(uint256 tokenCount) internal returns (address[] memory) {
        address[] memory tokens = new address[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = address(_deployMockERC20("Token", "TKN", 18));
        }
        return tokens;
    }

    function _createTokensArray(address token) internal pure returns (address[] memory) {
        address[] memory inputTokens = new address[](1);
        inputTokens[0] = token;
        return inputTokens;
    }

    function _whitelistTokensIfNeeded(address container, address[] memory tokens) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (IContainer(container).isTokenWhitelisted(tokens[i])) {
                continue;
            }
            vm.prank(roles.tokenManager);
            IContainer(container).whitelistToken(tokens[i]);
        }
    }
}
