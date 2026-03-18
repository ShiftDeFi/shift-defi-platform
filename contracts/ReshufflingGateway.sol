// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Errors} from "./libraries/helpers/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IVault} from "./interfaces/IVault.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IContainer} from "./interfaces/IContainer.sol";
import {ICrossChainContainer} from "./interfaces/ICrossChainContainer.sol";
import {IReshufflingGateway} from "./interfaces/IReshufflingGateway.sol";

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

    modifier onlyVault() {
        require(msg.sender == vault, NotVault(vault));
        _;
    }

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
        require(_swapRouter != address(0), Errors.ZeroAddress());

        vault = _vault;
        swapRouter = _swapRouter;

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
    function claimBridge(address bridgeAdapter, address token) external nonReentrant returns (uint256) {
        require(_whitelistedBridgeAdapters.contains(bridgeAdapter), NotWhitelistedBridgeAdapter(bridgeAdapter));
        require(_whitelistedTokens.contains(token), NotWhitelistedToken(token));

        uint256 claimedAmount = IBridgeAdapter(bridgeAdapter).claim(token);
        require(claimedAmount > 0, Errors.ZeroAmount());
        return claimedAmount;
    }

    /// @inheritdoc IReshufflingGateway
    function prepareLiquidity(
        ISwapRouter.SwapInstruction[] calldata swapInstructions
    ) external nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        uint256 length = swapInstructions.length;
        require(length > 0, Errors.IncorrectAmount());
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
        require(bridgeAdapters.length > 0, Errors.IncorrectAmount());
        require(bridgeAdapters.length == instructions.length, Errors.ArrayLengthMismatch());

        IContainer.ContainerType containerType = IContainer(container).containerType();
        require(
            containerType == IContainer.ContainerType.Principal,
            Errors.IncorrectContainerType(container, uint8(IContainer.ContainerType.Principal), uint8(containerType))
        );

        require(IVault(vault).isContainer(container), NotContainer(container));

        address agentAddress = ICrossChainContainer(container).peerContainer();
        require(agentAddress != address(0), Errors.ZeroAddress());

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
            require(
                IERC20(instructions[i].token).balanceOf(address(this)) >= instructions[i].amount,
                Errors.IncorrectAmount()
            );
            require(
                IContainer(container).isTokenWhitelisted(instructions[i].token),
                TokenNotWhitelistedOnContainer(instructions[i].token)
            );

            IERC20(instructions[i].token).safeIncreaseAllowance(bridgeAdapters[i], instructions[i].amount);
            uint256 amount = IBridgeAdapter(bridgeAdapters[i]).bridge(instructions[i], agentAddress);
            require(amount >= instructions[i].minTokenAmount, Errors.IncorrectAmount());
            emit SentToCrossChainContainer(container, instructions[i].token, amount);
        }
    }

    /// @inheritdoc IReshufflingGateway
    function sendToLocalContainer(
        address container,
        address[] memory tokens,
        uint256[] memory amounts
    ) external payable onlyReshufflingMode nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        require(tokens.length > 0, Errors.IncorrectAmount());
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
            require(balance >= amount, Errors.IncorrectAmount());
            IERC20(token).safeTransfer(container, amount);
            emit SentToLocalContainer(container, token, amount);
        }
    }
}
