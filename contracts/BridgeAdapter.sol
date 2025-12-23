// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {RingCacheLibrary} from "./libraries/helpers/RingCacheLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

abstract contract BridgeAdapter is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IBridgeAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using RingCacheLibrary for RingCacheLibrary.RingCache;

    bytes32 internal constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    mapping(address => mapping(uint256 => address)) public override bridgePaths;
    mapping(address => mapping(address => uint256)) public override claimableAmounts;
    mapping(address => bool) public override whitelistedBridgers;
    mapping(uint256 => address) public override peers;

    uint256 private _slippageCapPct;
    uint256 private constant MAX_SLIPPAGE_CAP_PCT = 10_000; // 100%

    RingCacheLibrary.RingCache private _cache;

    function __BridgeAdapter_init(address defaultAdmin, address governance) internal onlyInitializing {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNANCE_ROLE, governance);

        _cache.initialize("BRIDGE_CACHE", 8);
    }

    /// @inheritdoc IBridgeAdapter
    function setSlippageCapPct(uint256 slippageCapPct) external override onlyRole(GOVERNANCE_ROLE) {
        require(slippageCapPct <= MAX_SLIPPAGE_CAP_PCT, Errors.IncorrectAmount());
        _slippageCapPct = slippageCapPct;
        emit SlippageCapPctUpdated(_slippageCapPct);
    }

    /// @inheritdoc IBridgeAdapter
    function setBridgePath(
        address tokenOnSrc,
        uint256 chainId,
        address tokenOnDst
    ) external override onlyRole(GOVERNANCE_ROLE) {
        require(tokenOnSrc != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.ZeroAmount());
        require(bridgePaths[tokenOnSrc][chainId] != tokenOnDst, Errors.AlreadySet());

        bridgePaths[tokenOnSrc][chainId] = tokenOnDst;
        emit BridgePathUpdated(tokenOnSrc, chainId, tokenOnDst);
    }

    /// @inheritdoc IBridgeAdapter
    function setPeer(uint256 chainId, address peer) external override onlyRole(GOVERNANCE_ROLE) {
        require(peer != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.ZeroAmount());
        require(peers[chainId] != peer, Errors.AlreadySet());

        peers[chainId] = peer;
        emit PeerUpdated(chainId, peer);
    }

    /// @inheritdoc IBridgeAdapter
    function whitelistBridger(address bridger) external override onlyRole(GOVERNANCE_ROLE) {
        require(bridger != address(0), Errors.ZeroAddress());
        require(!whitelistedBridgers[bridger], Errors.AlreadyWhitelisted());
        whitelistedBridgers[bridger] = true;
        emit BridgerWhitelisted(bridger);
    }

    /// @inheritdoc IBridgeAdapter
    function blacklistBridger(address bridger) external override onlyRole(GOVERNANCE_ROLE) {
        require(bridger != address(0), Errors.ZeroAddress());
        require(whitelistedBridgers[bridger], Errors.AlreadyBlacklisted());
        whitelistedBridgers[bridger] = false;
        emit BridgerBlacklisted(bridger);
    }

    /// @inheritdoc IBridgeAdapter
    function bridge(
        BridgeInstruction calldata instruction,
        address receiver
    ) external virtual override nonReentrant returns (uint256) {
        require(receiver != address(0), Errors.ZeroAddress());
        require(whitelistedBridgers[msg.sender], BridgerNotWhitelisted(msg.sender));

        _validateBridgeInstruction(instruction);

        IERC20(instruction.token).safeTransferFrom(msg.sender, address(this), instruction.amount);
        uint256 bridgedAmount = _bridge(instruction, receiver, peers[instruction.chainTo]);

        _cacheInstruction(instruction, receiver);

        emit BridgeSent(instruction.token, bridgedAmount, instruction.chainTo);
        return bridgedAmount;
    }

    /// @inheritdoc IBridgeAdapter
    function claim(address token) external virtual override nonReentrant returns (uint256) {
        return _claim(msg.sender, token);
    }

    /// @inheritdoc IBridgeAdapter
    function retryBridge(
        BridgeInstruction calldata instruction,
        address receiver
    ) external virtual override nonReentrant {
        require(whitelistedBridgers[msg.sender], BridgerNotWhitelisted(msg.sender));

        _validateBridgeInstruction(instruction);

        bytes32 key = keccak256(abi.encode(instruction.token, instruction.chainTo, instruction.amount, receiver));
        require(_cache.exists(key), RingCacheLibrary.DoesNotExists(_cache.id, key));

        uint256 bridgedAmount = _bridge(instruction, receiver, peers[instruction.chainTo]);

        emit BridgeSent(instruction.token, bridgedAmount, instruction.chainTo);
    }

    function _isCached(address token, uint256 chainTo, uint256 amount, address receiver) private view returns (bool) {
        bytes32 key = keccak256(abi.encode(token, chainTo, amount, receiver));
        return _cache.exists(key);
    }

    function _cacheInstruction(BridgeInstruction calldata instruction, address receiver) private {
        bytes32 key = keccak256(abi.encode(instruction.token, instruction.chainTo, instruction.amount, receiver));
        _cache.add(key);
    }

    function _finalizeBridge(address claimer, address token, uint256 amount) internal {
        require(amount > 0, Errors.IncorrectAmount());
        require(claimer != address(0), Errors.ZeroAddress());
        require(token != address(0), Errors.ZeroAddress());

        claimableAmounts[claimer][token] += amount;
        emit Bridged(claimer, token, amount);
    }

    function _claim(address claimer, address token) internal returns (uint256) {
        require(claimer != address(0), Errors.ZeroAddress());
        require(token != address(0), Errors.ZeroAddress());

        uint256 amount = claimableAmounts[claimer][token];
        uint256 amountOnContract = IERC20(token).balanceOf(address(this));

        require(amount > 0 && amountOnContract > 0, Errors.ZeroAmount());
        require(amount <= amountOnContract, Errors.NotEnoughTokens(token, amount));

        claimableAmounts[claimer][token] = 0;

        IERC20(token).safeTransfer(claimer, amount);

        emit Claimed(claimer, token, amount);

        return amount;
    }

    function _validateBridgeInstruction(BridgeInstruction calldata instruction) internal view {
        require(instruction.token != address(0), Errors.ZeroAddress());
        require(instruction.chainTo > 0, Errors.ZeroAmount());
        require(instruction.amount > 0, Errors.ZeroAmount());
        require(
            bridgePaths[instruction.token][instruction.chainTo] != address(0),
            BadBridgePath(instruction.token, instruction.chainTo)
        );
        require(peers[instruction.chainTo] != address(0), PeerNotSet(instruction.chainTo));
        require(instruction.minTokenAmount <= instruction.amount, Errors.IncorrectAmount());
        uint256 slippageDelta = instruction.amount - instruction.minTokenAmount;
        require(
            slippageDelta * MAX_SLIPPAGE_CAP_PCT <= _slippageCapPct * instruction.amount,
            SlippageCapExceeded(slippageDelta, _slippageCapPct)
        );
    }
    function _bridge(
        BridgeInstruction calldata bridgeInstruction,
        address receiver,
        address peer
    ) internal virtual returns (uint256);

    function _validatePaylaod(bytes memory payload) internal virtual {}

    uint256[50] private __gap;
}
