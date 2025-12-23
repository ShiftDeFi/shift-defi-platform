// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Container} from "./Container.sol";

import {EnumerableAddressSetExtended} from "./libraries/helpers/EnumerableAddressSetExtended.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {IStrategyTemplate} from "./interfaces/IStrategyTemplate.sol";
import {IStrategyContainer} from "./interfaces/IStrategyContainer.sol";

abstract contract StrategyContainer is Initializable, ReentrancyGuardUpgradeable, Container, IStrategyContainer {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableAddressSetExtended for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 internal constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 internal constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 internal constant RESHUFFLING_MANAGER_ROLE = keccak256("RESHUFFLING_MANAGER_ROLE");
    bytes32 internal constant HARVEST_MANAGER_ROLE = keccak256("HARVEST_MANAGER_ROLE");

    EnumerableSet.AddressSet internal _strategies;

    mapping(address => uint256) internal _strategyNav0;
    mapping(address => uint256) internal _strategyNav1;

    uint256 internal _strategyEnterBitmask;
    uint256 internal _strategyExitBitmask;
    // @dev Bitmask to track if strategy's nav is unresolved during emergency resolution
    //      0: resolved, 1: unresolved
    uint256 internal _strategyUnresolvedNavBitmask;

    address internal _bridgeCollector; // address where funds stores after cross-chain migration

    address public treasury;
    address public priceOracle;

    uint256 public feePct;

    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_STRATEGIES = 255;

    bool internal _reshufflingMode;
    bool internal _isResolvingEmergency;

    modifier notResolvingEmergency() {
        require(!_isResolvingEmergency, EmergencyResolutionInProgress());
        _;
    }

    modifier notInReshufflingMode() {
        require(!_reshufflingMode, ActionUnavailableInReshufflingMode());
        _;
    }

    modifier onlyInReshufflingMode() {
        require(_reshufflingMode, ActionUnavailableNotInReshufflingMode());
        _;
    }

    // ---- Configuration ----

    function setBridgeCollector(address newBridgeCollector) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(newBridgeCollector != address(0), Errors.ZeroAddress());
        address oldBridgeCollector = _bridgeCollector;
        _bridgeCollector = newBridgeCollector;
        emit BridgeCollectorUpdated(oldBridgeCollector, newBridgeCollector);
    }

    function setTreasury(address newTreasury) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setTreasury(newTreasury);
    }

    function setPriceOracle(address newPriceOracle) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setPriceOracle(newPriceOracle);
    }

    function setFeePct(uint256 newFeePct) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setFeePct(newFeePct);
    }

    function _setPriceOracle(address newPriceOracle) internal {
        require(newPriceOracle != address(0), Errors.ZeroAddress());
        address oldPriceOracle = priceOracle;
        priceOracle = newPriceOracle;
        emit PriceOracleUpdated(oldPriceOracle, priceOracle);
    }

    function _setTreasury(address newTreasury) internal {
        require(newTreasury != address(0), Errors.ZeroAddress());
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    function _setFeePct(uint256 newFeePct) internal {
        require(newFeePct <= BPS, Errors.IncorrectAmount());
        uint256 previousFeePct = feePct;
        feePct = newFeePct;
        emit FeePctUpdated(previousFeePct, newFeePct);
    }

    // ---- Reshuffling mode management logic ----

    function enableReshufflingMode()
        external
        notResolvingEmergency
        notInReshufflingMode
        onlyRole(RESHUFFLING_MANAGER_ROLE)
    {
        require(_getCurrentBatchType() == CurrentBatchType.NoBatch, Errors.IncorrectContainerStatus());
        _reshufflingMode = true;
        emit ReshufflingModeUpdated(true);
    }

    function disableReshufflingMode()
        external
        onlyInReshufflingMode
        notResolvingEmergency
        onlyRole(RESHUFFLING_MANAGER_ROLE)
    {
        require(_getCurrentBatchType() == CurrentBatchType.NoBatch, Errors.IncorrectContainerStatus());
        _reshufflingMode = false;
        emit ReshufflingModeUpdated(false);
    }

    // ---- Strategies management logic ----

    function getStrategies() external view returns (address[] memory) {
        return _strategies.values();
    }

    function isStrategy(address strategy) external view returns (bool) {
        return _isStrategy(strategy);
    }

    function setStrategyInputTokens(
        address strategy,
        address[] calldata inputTokens
    ) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(_isStrategy(strategy), StrategyNotFound());
        _setStrategyInputTokens(strategy, inputTokens);
    }

    function setStrategyOutputTokens(
        address strategy,
        address[] calldata outputTokens
    ) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(_isStrategy(strategy), StrategyNotFound());
        _setStrategyOutputTokens(strategy, outputTokens);
    }

    function _setStrategyInputTokens(address strategy, address[] calldata inputTokens) internal {
        uint256 inputTokenNumber = inputTokens.length;
        require(inputTokenNumber > 0, Errors.ZeroArrayLength());

        for (uint256 i = 0; i < inputTokenNumber; ++i) {
            address inputToken = inputTokens[i];
            require(inputToken != address(0), Errors.ZeroAddress());
            require(_isTokenWhitelisted(inputToken), NotWhitelistedToken(inputToken));
        }
        IStrategyTemplate(strategy).setInputTokens(inputTokens);
        emit StrategyInputTokensUpdated(strategy);
    }

    function _setStrategyOutputTokens(address strategy, address[] calldata outputTokens) internal {
        uint256 outputTokenNumber = outputTokens.length;
        require(outputTokenNumber > 0, Errors.ZeroArrayLength());

        for (uint256 i = 0; i < outputTokenNumber; ++i) {
            address outputToken = outputTokens[i];
            require(outputToken != address(0), Errors.ZeroAddress());
            require(_isTokenWhitelisted(outputToken), NotWhitelistedToken(outputToken));
        }
        IStrategyTemplate(strategy).setOutputTokens(outputTokens);
        emit StrategyOutputTokensUpdated(strategy);
    }

    function _addStrategy(address strategy, address[] calldata inputTokens, address[] calldata outputTokens) internal {
        require(strategy != address(0), Errors.ZeroAddress());
        require(_strategies.length() < MAX_STRATEGIES, MaxStrategiesReached());

        _setStrategyInputTokens(strategy, inputTokens);
        _setStrategyOutputTokens(strategy, outputTokens);
        require(_strategies.add(strategy), StrategyAlreadyExists());

        emit StrategyAdded(strategy);
    }

    function _removeStrategy(address strategy) internal {
        require(strategy != address(0), Errors.ZeroAddress());
        require(_strategies.remove(strategy), StrategyNotFound());

        address[] memory inputTokens = IStrategyTemplate(strategy).getInputTokens();
        uint256 length = inputTokens.length;

        for (uint256 i = 0; i < length; ++i) {
            IERC20(inputTokens[i]).forceApprove(strategy, 0);
        }

        emit StrategyRemoved(strategy);
    }

    function _isStrategy(address strategy) private view returns (bool) {
        return _strategies.contains(strategy);
    }

    function getTotalNavs() public view returns (uint256, uint256) {
        uint256 totalNav0 = 0;
        uint256 totalNav1 = 0;
        uint256 length = _strategies.length();

        for (uint256 i = 0; i < length; ++i) {
            address strategy = _strategies.at(i);
            totalNav0 += _strategyNav0[strategy];
            totalNav1 += _strategyNav1[strategy];
        }

        return (totalNav0, totalNav1);
    }

    // ---- Strategy enter logic ----

    function _allStrategiesEntered() internal view returns (bool) {
        return _strategyEnterBitmask == (1 << _strategies.length()) - 1;
    }

    function _enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) internal {
        require(_isStrategy(strategy), StrategyNotFound());
        require(!isStrategyNavUnresolved(strategy), StrategyNavUnresolved(strategy));

        EnterStrategyLocalVars memory vars;

        address[] memory inputTokens = IStrategyTemplate(strategy).getInputTokens();
        vars.tokenNumber = inputTokens.length;
        require(inputAmounts.length == vars.tokenNumber, Errors.ArrayLengthMismatch());

        (, vars.strategyIndex) = _strategies.indexOf(strategy);

        vars.enterBitmask = _strategyEnterBitmask;
        vars.strategyMask = 1 << vars.strategyIndex;
        require(vars.enterBitmask & vars.strategyMask == 0, StrategyAlreadyEntered(strategy));
        _strategyEnterBitmask = vars.enterBitmask | vars.strategyMask;

        vars.nav0 = IStrategyTemplate(strategy).harvest();
        _strategyNav0[strategy] = vars.nav0;

        for (uint256 i = 0; i < vars.tokenNumber; ++i) {
            IERC20(inputTokens[i]).safeIncreaseAllowance(strategy, inputAmounts[i]);
        }

        uint256[] memory remainingAmounts;
        (vars.nav1, vars.hasRemainder, remainingAmounts) = IStrategyTemplate(strategy).enter(inputAmounts, minNavDelta);
        _strategyNav1[strategy] = vars.nav1;

        require(vars.nav1 > vars.nav0, IncorrectEnterNav(vars.nav0, vars.nav1));

        if (vars.hasRemainder) {
            require(remainingAmounts.length == vars.tokenNumber, Errors.ArrayLengthMismatch());

            for (uint256 i = 0; i < vars.tokenNumber; ++i) {
                if (remainingAmounts[i] > 0) {
                    IERC20(inputTokens[i]).safeTransferFrom(strategy, address(this), remainingAmounts[i]);
                }
            }
        }

        emit StrategyEntered(strategy, vars.nav0, vars.nav1, vars.hasRemainder);
    }

    function enterInReshufflingMode(
        address strategy,
        uint256[] calldata inputAmounts,
        uint256 minNavDelta
    ) external nonReentrant onlyInReshufflingMode onlyRole(RESHUFFLING_MANAGER_ROLE) {
        require(_isStrategy(strategy), StrategyNotFound());
        require(!isStrategyNavUnresolved(strategy), StrategyNavUnresolved(strategy));

        address[] memory inputTokens = IStrategyTemplate(strategy).getInputTokens();
        uint256 tokenNumber = inputTokens.length;

        require(tokenNumber == inputAmounts.length, Errors.ArrayLengthMismatch());

        uint256 nav0 = IStrategyTemplate(strategy).harvest();

        for (uint256 i = 0; i < tokenNumber; ++i) {
            IERC20(inputTokens[i]).safeIncreaseAllowance(strategy, inputAmounts[i]);
        }

        (uint256 nav1, bool hasRemainder, uint256[] memory remainingAmounts) = IStrategyTemplate(strategy).enter(
            inputAmounts,
            minNavDelta
        );

        if (hasRemainder) {
            uint256 length = remainingAmounts.length;
            require(length == inputTokens.length, Errors.ArrayLengthMismatch());
            for (uint256 i = 0; i < length; ++i) {
                require(_isTokenWhitelisted(inputTokens[i]), NotWhitelistedToken(inputTokens[i]));
                IERC20(inputTokens[i]).safeTransferFrom(strategy, address(this), remainingAmounts[i]);
            }
        }
        emit StrategyEntered(strategy, nav0, nav1, hasRemainder);
    }

    // ---- Strategy exit logic ----

    function exitInReshufflingMode(
        address strategy,
        uint256 share,
        uint256 maxNavDelta
    ) external nonReentrant onlyInReshufflingMode onlyRole(RESHUFFLING_MANAGER_ROLE) {
        require(share > 0, Errors.ZeroAmount());
        require(share <= BPS, Errors.IncorrectAmount());
        require(_isStrategy(strategy), StrategyNotFound());
        require(!isStrategyNavUnresolved(strategy), StrategyNavUnresolved(strategy));

        IStrategyTemplate(strategy).harvest();
        (address[] memory tokens, uint256[] memory amounts) = IStrategyTemplate(strategy).exit(share, maxNavDelta);

        uint256 length = tokens.length;
        require(length == amounts.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            if (_isTokenWhitelisted(tokens[i])) {
                IERC20(tokens[i]).safeTransferFrom(strategy, address(this), amounts[i]);
            }
        }
        emit StrategyExited(strategy, share);
    }

    function _allStrategiesExited() internal view returns (bool) {
        return _strategyExitBitmask == (1 << _strategies.length()) - 1;
    }

    function _exitStrategy(address strategy, uint256 share, uint256 maxNavDelta) internal {
        require(_isStrategy(strategy), StrategyNotFound());
        require(!isStrategyNavUnresolved(strategy), StrategyNavUnresolved(strategy));

        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        uint256 mask = 1 << strategyIndex;

        require(_strategyExitBitmask & mask == 0, StrategyAlreadyExited(strategy));
        _strategyExitBitmask |= mask;

        IStrategyTemplate(strategy).harvest();

        (address[] memory tokens, uint256[] memory amounts) = IStrategyTemplate(strategy).exit(share, maxNavDelta);

        uint256 length = tokens.length;
        require(length == amounts.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            if (_isTokenWhitelisted(tokens[i])) {
                IERC20(tokens[i]).safeTransferFrom(strategy, address(this), amounts[i]);
            }
        }

        emit StrategyExited(strategy, share);
    }

    // ---- Emergency resolution logic ----

    function startEmergencyResolution() external {
        require(_isStrategy(msg.sender), StrategyNotFound());

        (, uint256 strategyIndex) = _strategies.indexOf(msg.sender);
        uint256 mask = 1 << strategyIndex;
        _strategyUnresolvedNavBitmask |= mask;

        if (!_isResolvingEmergency) {
            _isResolvingEmergency = true;
            emit EmergencyResolutionStarted(msg.sender);
        }
    }

    function isResolvingEmergency() external view returns (bool) {
        return _isResolvingEmergency;
    }

    function completeEmergencyResolution() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        require(_isResolvingEmergency, NotResolvingEmergency());
        _isResolvingEmergency = false;
        require(_strategyUnresolvedNavBitmask == 0, EmergencyResolutionNotCompleted(_strategyUnresolvedNavBitmask));
        emit EmergencyResolutionCompleted();
    }

    function resolveStrategyNav(uint256 resolvedNav) external {
        require(_isStrategy(msg.sender), StrategyNotFound());
        require(isStrategyNavUnresolved(msg.sender), StrategyNavAlreadyResolved(msg.sender));

        (, uint256 strategyIndex) = _strategies.indexOf(msg.sender);
        uint256 mask = 1 << strategyIndex;
        _strategyUnresolvedNavBitmask &= ~mask;

        emit StrategyNavResolved(msg.sender, resolvedNav);
    }

    function isStrategyNavUnresolved(address strategy) public view returns (bool) {
        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        uint256 mask = 1 << strategyIndex;
        return _strategyUnresolvedNavBitmask & mask != 0;
    }

    function _getCurrentBatchType() internal view virtual returns (CurrentBatchType);

    uint256[50] private __gap;
}
