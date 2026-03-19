// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {IContainer} from "./interfaces/IContainer.sol";
import {ICrossChainContainer} from "./interfaces/ICrossChainContainer.sol";
import {IReshufflingGateway} from "./interfaces/IReshufflingGateway.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IVault} from "./interfaces/IVault.sol";

import {Errors} from "./libraries/Errors.sol";

contract ReshufflingGateway is AccessControlUpgradeable, ReentrancyGuardUpgradeable, IReshufflingGateway {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant RESHUFFLING_MANAGER_ROLE = keccak256("RESHUFFLING_MANAGER_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    address public vault;
    address public swapRouter;

    EnumerableSet.AddressSet private _whitelistedTokens;
    EnumerableSet.AddressSet private _whitelistedBridgeAdapters;

    modifier onlyReshufflingMode() {
        require(IVault(vault).isReshuffling(), VaultNotInReshufflingMode());
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ReshufflingGateway contract.
     * @param _vault The address of the vault contract.
     * @param _swapRouter The address of the swap router contract.
     * @param _defaultAdmin The address to receive DEFAULT_ADMIN_ROLE.
     * @param _reshufflingManager The address to receive RESHUFFLING_MANAGER_ROLE.
     * @param _whitelistManager The address to receive WHITELIST_MANAGER_ROLE.
     */
    function initialize(
        address _vault,
        address _swapRouter,
        address _defaultAdmin,
        address _reshufflingManager,
        address _whitelistManager
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        require(_vault != address(0), Errors.ZeroAddress());

        vault = _vault;
        _setSwapRouter(_swapRouter);

        require(_defaultAdmin != address(0), Errors.ZeroAddress());
        require(_reshufflingManager != address(0), Errors.ZeroAddress());
        require(_whitelistManager != address(0), Errors.ZeroAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(RESHUFFLING_MANAGER_ROLE, _reshufflingManager);
        _grantRole(WHITELIST_MANAGER_ROLE, _whitelistManager);
    }

    /// @inheritdoc IReshufflingGateway
    function getWhitelistedTokens() external view returns (address[] memory) {
        return _whitelistedTokens.values();
    }

    /// @inheritdoc IReshufflingGateway
    function whitelistToken(address token) external onlyRole(WHITELIST_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(_whitelistedTokens.add(token), AlreadyWhitelistedToken());
        emit TokenWhitelisted(token);
    }

    /// @inheritdoc IReshufflingGateway
    function whitelistBridgeAdapter(address bridgeAdapter) external onlyRole(WHITELIST_MANAGER_ROLE) {
        require(bridgeAdapter != address(0), Errors.ZeroAddress());
        require(_whitelistedBridgeAdapters.add(bridgeAdapter), AlreadyWhitelistedBridgeAdapter());
        emit BridgeAdapterWhitelisted(bridgeAdapter);
    }

    /// @inheritdoc IReshufflingGateway
    function blacklistToken(address token) external onlyRole(WHITELIST_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(_whitelistedTokens.remove(token), NotWhitelistedToken(token));
        emit TokenBlacklisted(token);
    }

    /// @inheritdoc IReshufflingGateway
    function blacklistBridgeAdapter(address bridgeAdapter) external onlyRole(WHITELIST_MANAGER_ROLE) {
        require(bridgeAdapter != address(0), Errors.ZeroAddress());
        require(_whitelistedBridgeAdapters.remove(bridgeAdapter), NotWhitelistedBridgeAdapter(bridgeAdapter));
        emit BridgeAdapterBlacklisted(bridgeAdapter);
    }

    /// @inheritdoc IReshufflingGateway
    function setSwapRouter(address newSwapRouter) external onlyRole(WHITELIST_MANAGER_ROLE) {
        _setSwapRouter(newSwapRouter);
    }

    function _setSwapRouter(address newSwapRouter) internal {
        require(newSwapRouter != address(0), Errors.ZeroAddress());
        swapRouter = newSwapRouter;
        address previousSwapRouter = swapRouter;
        if (previousSwapRouter != address(0)) {
            _dropApprovesFromWhitelistedTokens(previousSwapRouter);
        }
        emit SwapRouterUpdated(previousSwapRouter, newSwapRouter);
    }

    function _dropApprovesFromWhitelistedTokens(address addr) internal {
        uint256 length = _whitelistedTokens.length();
        for (uint256 i = 0; i < length; ++i) {
            address token = _whitelistedTokens.at(i);
            IERC20(token).forceApprove(addr, 0);
        }
    }

    /// @inheritdoc IReshufflingGateway
    function claimBridge(address bridgeAdapter, address token) external nonReentrant returns (uint256) {
        require(_whitelistedBridgeAdapters.contains(bridgeAdapter), NotWhitelistedBridgeAdapter(bridgeAdapter));
        require(_whitelistedTokens.contains(token), NotWhitelistedToken(token));

        uint256 claimedAmount = IBridgeAdapter(bridgeAdapter).claim(token);
        require(claimedAmount > 0, NothingClaimed(bridgeAdapter, token));
        return claimedAmount;
    }

    /// @inheritdoc IReshufflingGateway
    function prepareLiquidity(
        ISwapRouter.SwapInstruction[] calldata swapInstructions
    ) external nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        uint256 length = swapInstructions.length;
        require(length > 0, Errors.ZeroArrayLength());
        for (uint256 i = 0; i < length; i++) {
            require(
                _whitelistedTokens.contains(swapInstructions[i].tokenIn),
                NotWhitelistedToken(swapInstructions[i].tokenIn)
            );
            require(
                _whitelistedTokens.contains(swapInstructions[i].tokenOut),
                NotWhitelistedToken(swapInstructions[i].tokenOut)
            );

            IERC20(swapInstructions[i].tokenIn).forceApprove(swapRouter, swapInstructions[i].amountIn);
            ISwapRouter(swapRouter).swap(swapInstructions[i]);
        }
    }

    /// @inheritdoc IReshufflingGateway
    function sendToCrossChainContainer(
        address container,
        address[] memory bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata instructions
    ) external payable onlyReshufflingMode nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        require(bridgeAdapters.length > 0, Errors.ZeroArrayLength());
        require(bridgeAdapters.length == instructions.length, Errors.ArrayLengthMismatch());

        IContainer.ContainerType containerType = IContainer(container).containerType();
        require(
            containerType == IContainer.ContainerType.Principal,
            Errors.IncorrectContainerType(container, uint8(IContainer.ContainerType.Principal), uint8(containerType))
        );

        require(IVault(vault).isContainer(container), NotContainer(container));

        address peerContainer = ICrossChainContainer(container).peerContainer();
        require(peerContainer != address(0), IncorrectPeerContainer(container));

        uint256 containerRemoteChainId = ICrossChainContainer(container).remoteChainId();
        uint256 length = instructions.length;
        for (uint256 i = 0; i < length; ++i) {
            require(
                _whitelistedBridgeAdapters.contains(bridgeAdapters[i]),
                NotWhitelistedBridgeAdapter(bridgeAdapters[i])
            );
            require(
                containerRemoteChainId == instructions[i].chainTo,
                WrongRemoteChainId(instructions[i].chainTo, containerRemoteChainId)
            );
            require(_whitelistedTokens.contains(instructions[i].token), NotWhitelistedToken(instructions[i].token));
            uint256 balance = IERC20(instructions[i].token).balanceOf(address(this));
            require(
                balance >= instructions[i].amount,
                Errors.NotEnoughTokens(instructions[i].token, instructions[i].amount, balance)
            );
            require(
                IContainer(container).isTokenWhitelisted(instructions[i].token),
                TokenNotWhitelistedOnContainer(instructions[i].token)
            );

            IERC20(instructions[i].token).safeIncreaseAllowance(bridgeAdapters[i], instructions[i].amount);
            uint256 amount = IBridgeAdapter(bridgeAdapters[i]).bridge(instructions[i], peerContainer);
            require(
                amount >= instructions[i].minTokenAmount,
                NotEnoughTokensBridged(instructions[i].token, instructions[i].minTokenAmount, amount)
            );
            emit SentToCrossChainContainer(container, instructions[i].token, amount);
        }
    }

    /// @inheritdoc IReshufflingGateway
    function sendToLocalContainer(
        address container,
        address[] memory tokens,
        uint256[] memory amounts
    ) external payable onlyReshufflingMode nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        require(tokens.length > 0, Errors.ZeroArrayLength());
        require(tokens.length == amounts.length, Errors.ArrayLengthMismatch());
        require(IVault(vault).isContainer(container), NotContainer(container));

        IContainer.ContainerType containerType = IContainer(container).containerType();
        require(
            containerType == IContainer.ContainerType.Local,
            Errors.IncorrectContainerType(container, uint8(IContainer.ContainerType.Local), uint8(containerType))
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            require(_whitelistedTokens.contains(token), NotWhitelistedToken(token));
            require(IContainer(container).isTokenWhitelisted(token), TokenNotWhitelistedOnContainer(token));
            uint256 balance = IERC20(token).balanceOf(address(this));
            require(balance >= amount, Errors.NotEnoughTokens(token, amount, balance));
            IERC20(token).safeTransfer(container, amount);
            emit SentToLocalContainer(container, token, amount);
        }
    }
}
