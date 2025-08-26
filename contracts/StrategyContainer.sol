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
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";

abstract contract StrategyContainer is Initializable, ReentrancyGuardUpgradeable, Container, IStrategyContainer {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableAddressSetExtended for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    bytes32 internal constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 internal constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 internal constant RESHUFFLING_MANAGER_ROLE = keccak256("RESHUFFLING_MANAGER_ROLE");
    uint256 internal constant MIN_HARVEST_AGE = 3600;

    EnumerableSet.AddressSet internal _strategies;

    mapping(address => uint256) internal _strategyNav0;
    mapping(address => uint256) internal _strategyNav1;
    mapping(address => uint256) internal _strategyHarvestTimestamp;

    uint256 internal _maxHarvestAge;

    uint256 internal _strategyHarvestBitmask;
    uint256 internal _strategyEnterBitmask;
    uint256 internal _strategyExitBitmask;

    address internal _bridgeCollector; // address where funds stores after cross-chain migration

    address public override treasury;
    address public override priceOracle;

    uint256 public override feePct;

    uint256 private constant BPS = 10_000;

    bool private _reshufflingMode;

    function __StrategyContainer_init() internal onlyInitializing {
        _setMaxHarvestAge(MIN_HARVEST_AGE);
    }

    function getStrategies() external view returns (address[] memory) {
        return _strategies.values();
    }

    // ---- Strategies management logic ----

    function isStrategy(address strategy) external view returns (bool) {
        return _isStrategy(strategy);
    }

    function addStrategy(address strategy) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(strategy != address(0), Errors.ZeroAddress());
        require(_strategies.add(strategy), StrategyAlreadyExists());

        address[] memory inputTokens = IStrategyTemplate(strategy).inputTokens();
        uint256 length = inputTokens.length;

        for (uint256 i = 0; i < length; ++i) {
            require(_isTokenWhitelisted(inputTokens[i]), NotWhitelistedToken(inputTokens[i]));
            IERC20(inputTokens[i]).approve(strategy, type(uint256).max);
        }

        emit StrategyAdded(strategy);
    }

    function removeStrategy(address strategy) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(strategy != address(0), Errors.ZeroAddress());
        require(_strategies.remove(strategy), StrategyNotFound());

        address[] memory inputTokens = IStrategyTemplate(strategy).inputTokens();
        uint256 length = inputTokens.length;

        for (uint256 i = 0; i < length; ++i) {
            IERC20(inputTokens[i]).approve(strategy, 0);
        }

        emit StrategyRemoved(strategy);
    }

    function enterInReshufflingMode(
        address strategy,
        uint256[] calldata inputAmounts,
        uint256 minNavDelta
    ) external nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        _enterStrategyInReshufflingMode(strategy, inputAmounts, minNavDelta);
    }

    function exitInReshufflingMode(
        address strategy,
        uint256 share,
        uint256 minNavDelta
    ) external nonReentrant onlyRole(RESHUFFLING_MANAGER_ROLE) {
        _exitStrategyInReshufflingMode(strategy, share, minNavDelta);
    }

    function enableReshufflingMode() external onlyRole(STRATEGY_MANAGER_ROLE) {
        _reshufflingMode = true;
    }

    function disableReshufflingMode() external onlyRole(RESHUFFLING_MANAGER_ROLE) {
        _reshufflingMode = false;
    }

    function setBridgeCollector(address newBridgeCollector) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setBridgeCollector(newBridgeCollector);
    }

    function setMaxHarvestAge(uint256 maxHarvestAge) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setMaxHarvestAge(maxHarvestAge);
    }

    function setTreasury(address newTreasury) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setTreasury(newTreasury);
    }

    function setFeePct(uint256 newFeePct) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setFeePct(newFeePct);
    }

    function setPriceOracle(address newPriceOracle) external onlyRole(STRATEGY_MANAGER_ROLE) {
        _setPriceOracle(newPriceOracle);
    }

    function _setPriceOracle(address newPriceOracle) internal {
        require(newPriceOracle != address(0), Errors.ZeroAddress());
        address oldPriceOracle = priceOracle;
        priceOracle = newPriceOracle;
        emit PriceOracleUpdated(oldPriceOracle, priceOracle);
    }

    function _setMaxHarvestAge(uint256 maxHarvestAge) internal {
        require(maxHarvestAge >= MIN_HARVEST_AGE, Errors.IncorrectAmount());
        uint256 previousMaxHarvestAge = _maxHarvestAge;
        _maxHarvestAge = maxHarvestAge;
        emit MaxHarvestAgeUpdated(previousMaxHarvestAge, maxHarvestAge);
    }

    function _setTreasury(address newTreasury) internal {
        require(newTreasury != address(0), Errors.ZeroAddress());
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, treasury);
    }

    function _setFeePct(uint256 newFeePct) internal {
        require(newFeePct <= BPS, Errors.IncorrectAmount());
        uint256 previousFeePct = feePct;
        feePct = newFeePct;
        emit FeePctUpdated(previousFeePct, feePct);
    }

    function _setBridgeCollector(address newBridgeCollector) internal {
        require(newBridgeCollector != address(0), Errors.ZeroAddress());
        address oldBridgeCollector = _bridgeCollector;
        _bridgeCollector = newBridgeCollector;
        emit BridgeCollectorUpdated(oldBridgeCollector, newBridgeCollector);
    }

    function _isStrategy(address strategy) private view returns (bool) {
        return _strategies.contains(strategy);
    }

    function _isReshufflingMode() internal view returns (bool) {
        return _reshufflingMode;
    }

    // ---- Strategy harvest logic ----

    function manualHarvest(address strategy) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(_isStrategy(strategy), StrategyNotFound());

        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        require(_isHarvestRequired(strategy, strategyIndex), StrategyAlreadyHarvested(strategy));
        _harvestStrategy(strategy, strategyIndex);
    }

    function getTotalNav0() public view returns (uint256) {
        uint256 totalNav0 = 0;
        for (uint256 i = 0; i < _strategies.length(); ++i) {
            address strategy = _strategies.at(i);
            totalNav0 += _strategyNav0[strategy];
        }
        return totalNav0;
    }

    function getTotalNav1() public view returns (uint256) {
        uint256 totalNav1 = 0;
        for (uint256 i = 0; i < _strategies.length(); ++i) {
            address strategy = _strategies.at(i);
            totalNav1 += _strategyNav1[strategy];
        }
        return totalNav1;
    }

    function hasHarvestedThisBatch(address strategy) external view returns (bool) {
        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        return _hasHarvestedThisBatch(strategyIndex);
    }

    function _checkIfHarvestsAreUpToDate() internal view {
        uint256 length = _strategies.length();
        for (uint256 i = 0; i < length; ++i) {
            address strategy = _strategies.at(i);
            if (_isHarvestOutdated(strategy)) {
                revert StrategyHarvestOutdated(strategy);
            }
        }
    }

    function _getTotalNavs() internal view returns (uint256, uint256) {
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

    function _hasHarvestedThisBatch(uint256 strategyIndex) private view returns (bool) {
        return _strategyHarvestBitmask & (1 << strategyIndex) != 0;
    }

    function _isHarvestOutdated(address strategy) private view returns (bool) {
        return _strategyHarvestTimestamp[strategy] + _maxHarvestAge < block.timestamp;
    }

    function _isHarvestRequired(address strategy, uint256 strategyIndex) private view returns (bool) {
        if (_hasHarvestedThisBatch(strategyIndex)) {
            return _isHarvestOutdated(strategy);
        }
        return true;
    }

    function setStrategyHarvestTimestamp(address strategy) external onlyRole(STRATEGY_MANAGER_ROLE) {
        require(_isStrategy(strategy), StrategyNotFound());
        _strategyHarvestTimestamp[strategy] = block.timestamp;
    }

    function _harvestStrategy(address strategy, uint256 strategyIndex) internal returns (uint256) {
        HarvestStrategyLocalVars memory vars;

        _strategyHarvestBitmask |= 1 << strategyIndex;
        _strategyHarvestTimestamp[strategy] = block.timestamp;

        vars.nav0New = IStrategyTemplate(strategy).harvest();

        if (_hasEnteredThisBatch(strategyIndex)) {
            require(vars.nav0New > 0, IncorrectNav0());
            vars.nav0Previous = _strategyNav0[strategy];

            if (vars.nav0New > vars.nav0Previous) {
                vars.nav0Delta = vars.nav0New - vars.nav0Previous;
                _strategyNav1[strategy] += vars.nav0Delta;
            } else {
                vars.nav0Delta = vars.nav0Previous - vars.nav0New;
                _strategyNav1[strategy] -= vars.nav0Delta;
            }
        }

        _strategyNav0[strategy] = vars.nav0New;

        emit StrategyHarvested(strategy, vars.nav0New);
        return vars.nav0New;
    }

    // ---- Strategy enter logic ----
    function _hasEnteredThisBatch(uint256 strategyIndex) private view returns (bool) {
        return _strategyEnterBitmask & (1 << strategyIndex) != 0;
    }

    function _allStrategiesEntered() internal view returns (bool) {
        return _strategyEnterBitmask == (1 << _strategies.length()) - 1;
    }

    function _enterStrategy(address strategy, uint256[] calldata inputAmounts, uint256 minNavDelta) internal {
        require(_isStrategy(strategy), StrategyNotFound());
        require(!_reshufflingMode, ActionUnavailableInReshufflingMode());

        EnterStrategyLocalVars memory vars;

        address[] memory inputTokens = IStrategyTemplate(strategy).inputTokens();
        uint256 length = inputTokens.length;
        require(inputAmounts.length == length, Errors.ArrayLengthMismatch());

        (, vars.strategyIndex) = _strategies.indexOf(strategy);

        require(!_hasEnteredThisBatch(vars.strategyIndex), StrategyAlreadyEntered(strategy));

        if (_isHarvestRequired(strategy, vars.strategyIndex)) {
            _harvestStrategy(strategy, vars.strategyIndex);
        }

        _strategyEnterBitmask |= 1 << vars.strategyIndex;

        uint256[] memory remainingAmounts;
        (vars.nav1, vars.hasRemainder, remainingAmounts) = IStrategyTemplate(strategy).enter(inputAmounts, minNavDelta);
        _strategyNav1[strategy] = vars.nav1;

        if (vars.hasRemainder) {
            require(remainingAmounts.length == length, Errors.ArrayLengthMismatch());

            for (uint256 i = 0; i < length; ++i) {
                if (remainingAmounts[i] > 0) {
                    IERC20(inputTokens[i]).safeTransferFrom(strategy, address(this), remainingAmounts[i]);
                }
            }
        }

        emit StrategyEntered(strategy, vars.nav1, vars.hasRemainder);
    }

    function _enterStrategyInReshufflingMode(
        address strategy,
        uint256[] calldata inputAmounts,
        uint256 minNavDelta
    ) internal {
        require(_isStrategy(strategy), StrategyNotFound());
        require(_reshufflingMode, ActionUnavailableInReshufflingMode());

        address[] memory inputTokens = IStrategyTemplate(strategy).inputTokens();
        require(inputAmounts.length == inputAmounts.length, Errors.ArrayLengthMismatch());

        IStrategyTemplate(strategy).harvest();
        (uint256 nav1, bool hasRemainder, uint256[] memory remainingAmounts) = IStrategyTemplate(strategy).enter(
            inputAmounts,
            minNavDelta
        );

        if (hasRemainder) {
            uint256 length = remainingAmounts.length;
            require(length == remainingAmounts.length, Errors.ArrayLengthMismatch());
            for (uint256 i = 0; i < length; ++i) {
                require(_isTokenWhitelisted(inputTokens[i]), NotWhitelistedToken(inputTokens[i]));
                IERC20(inputTokens[i]).safeTransferFrom(strategy, address(this), remainingAmounts[i]);
            }
        }
        emit StrategyEntered(strategy, nav1, hasRemainder);
    }

    function _exitStrategyInReshufflingMode(address strategy, uint256 share, uint256 minNavDelta) internal {
        require(share > 0, Errors.ZeroAmount());
        require(share <= BPS, Errors.IncorrectAmount());
        require(_isStrategy(strategy), StrategyNotFound());
        require(_reshufflingMode, ActionUnavailableInReshufflingMode());

        IStrategyTemplate(strategy).harvest();
        (address[] memory tokens, uint256[] memory amounts) = IStrategyTemplate(strategy).exit(share, minNavDelta);

        uint256 length = tokens.length;
        require(length == amounts.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            require(_isTokenWhitelisted(tokens[i]), NotWhitelistedToken(tokens[i]));
            IERC20(tokens[i]).safeTransferFrom(strategy, address(this), amounts[i]);
        }
        emit StrategyExited(strategy, share);
    }

    // ---- Strategy exit logic ----

    function _allStrategiesExited() internal view returns (bool) {
        return _strategyExitBitmask == (1 << _strategies.length()) - 1;
    }

    function _exitStrategy(address strategy, uint256 share, uint256 minNavDelta) internal {
        require(_isStrategy(strategy), StrategyNotFound());
        require(!_reshufflingMode, ActionUnavailableInReshufflingMode());

        (, uint256 strategyIndex) = _strategies.indexOf(strategy);
        uint256 mask = 1 << strategyIndex;

        require(_strategyExitBitmask & mask == 0, StrategyAlreadyExited(strategy));
        _strategyExitBitmask |= mask;

        (address[] memory tokens, uint256[] memory amounts) = IStrategyTemplate(strategy).exit(share, minNavDelta);

        uint256 length = tokens.length;
        require(length == amounts.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ++i) {
            require(_isTokenWhitelisted(tokens[i]), NotWhitelistedToken(tokens[i]));
            IERC20(tokens[i]).safeTransferFrom(strategy, address(this), amounts[i]);
        }

        emit StrategyExited(strategy, share);
    }

    // TODO: Implement retry logic

    uint256[50] private __gap;
}
