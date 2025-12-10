// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {StrategyStateLib} from "./libraries/StrategyStateLib.sol";

import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IStrategyContainer} from "./interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "./interfaces/IStrategyTemplate.sol";
import {IContainer} from "./interfaces/IContainer.sol";
import {IPriceOracleAggregator} from "./interfaces/IPriceOracleAggregator.sol";

abstract contract StrategyTemplate is Initializable, ReentrancyGuardUpgradeable, IStrategyTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using StrategyStateLib for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 private constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 private constant HARVEST_MANAGER_ROLE = keccak256("HARVEST_MANAGER_ROLE");

    bytes32 internal constant NO_ALLOCATION_STATE_ID = bytes32(0);
    uint256 internal constant BPS = 10_000;

    address internal _strategyContainer;
    address internal _notion;
    bytes32 private _targetStateId;
    bytes32 private _currentStateId = NO_ALLOCATION_STATE_ID;

    mapping(bytes32 => uint256) private _stateBitmasks;

    EnumerableSet.Bytes32Set private _stateIds;
    EnumerableSet.AddressSet private _inputTokens;
    EnumerableSet.AddressSet private _outputTokens;

    bool private _navResolutionMode;

    /* Modifiers */

    modifier onlyStrategyContainer() {
        require(_strategyContainer != address(0), Errors.ZeroAddress());
        require(msg.sender == _strategyContainer, Errors.Unauthorized());
        _;
    }

    modifier onlyStrategyContainerOrHarvestManager() {
        address strategyContainerCached = _strategyContainer;
        bool isHarvestManager = AccessControlUpgradeable(strategyContainerCached).hasRole(
            HARVEST_MANAGER_ROLE,
            msg.sender
        );
        require(isHarvestManager || msg.sender == strategyContainerCached, Errors.Unauthorized());
        _;
    }

    modifier onlyStrategyContainerOrEmergencyManager() {
        address strategyContainerCached = _strategyContainer;
        bool isEmergencyManager = AccessControlUpgradeable(strategyContainerCached).hasRole(
            EMERGENCY_MANAGER_ROLE,
            msg.sender
        );
        require(isEmergencyManager || msg.sender == strategyContainerCached, Errors.Unauthorized());
        _;
    }

    modifier onlyEmergencyManager() {
        require(
            AccessControlUpgradeable(_strategyContainer).hasRole(EMERGENCY_MANAGER_ROLE, msg.sender),
            Errors.Unauthorized()
        );
        _;
    }

    /* Views */

    function currentStateId() public view returns (bytes32) {
        return _currentStateId;
    }

    function currentStateNav() public view returns (uint256) {
        return stateNav(_currentStateId);
    }

    function getInputTokens() external view override returns (address[] memory) {
        return _inputTokens.values();
    }

    function getOutputTokens() external view override returns (address[] memory) {
        return _outputTokens.values();
    }

    function isNavResolutionMode() public view returns (bool) {
        return _navResolutionMode;
    }

    function stateNav(bytes32 stateId) public view virtual returns (uint256);

    /* Configuration functions */

    /*
    Post initialization hook
    Set strategy container and notion token
    */
    function __StrategyTemplate_init(address strategyContainer) internal onlyInitializing {
        require(strategyContainer != address(0), Errors.ZeroAddress());
        address notion = IContainer(strategyContainer).notion();
        require(notion != address(0), Errors.ZeroAddress());

        _strategyContainer = strategyContainer;
        _notion = notion;

        __ReentrancyGuard_init();
    }

    function setInputTokens(address[] calldata inputTokens) external override onlyStrategyContainer {
        require(inputTokens.length > 0, Errors.ZeroArrayLength());
        for (uint256 i = 0; i < inputTokens.length; ) {
            require(inputTokens[i] != address(0), Errors.ZeroAddress());
            require(_inputTokens.add(inputTokens[i]), Errors.TokenAlreadySet(inputTokens[i]));
            emit InputTokenSet(inputTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setOutputTokens(address[] calldata outputTokens) external override onlyStrategyContainer {
        require(outputTokens.length > 0, Errors.ZeroArrayLength());
        for (uint256 i = 0; i < outputTokens.length; ) {
            require(outputTokens[i] != address(0), Errors.ZeroAddress());
            require(_outputTokens.add(outputTokens[i]), Errors.TokenAlreadySet(outputTokens[i]));
            emit OutputTokenSet(outputTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setState(
        bytes32 stateId,
        bool isTargetState,
        bool isProtocolState,
        bool isTokenState,
        uint8 height
    ) internal {
        require(stateId != NO_ALLOCATION_STATE_ID, Errors.IncorrectInput());
        _stateBitmasks[stateId] = StrategyStateLib.createState(isTargetState, isProtocolState, isTokenState, height);
        if (isTargetState) {
            require(_targetStateId == bytes32(0), TargetStateAlreadySet());
            _targetStateId = stateId;
        }
        require(_stateIds.add(stateId), StateAlreadyExists(stateId));
    }

    function enter(
        uint256[] calldata amounts,
        uint256 minNavDelta
    ) external payable onlyStrategyContainer nonReentrant returns (uint256, bool, uint256[] memory) {
        EnterLocalVars memory vars = _enter(amounts, minNavDelta, true);
        return (vars.stateToNavAfterEnter, vars.hasRemainder, vars.remainingAmounts);
    }

    function reenterToState(bytes32 stateId, uint256 minNavDelta) external payable onlyEmergencyManager nonReentrant {
        _enterToState(stateId, minNavDelta);
    }

    function _enter(
        uint256[] memory amounts,
        uint256 minNavDelta,
        bool needPrepareForAgent
    ) private returns (EnterLocalVars memory) {
        EnterLocalVars memory vars;

        vars.currentStateId = _currentStateId;

        require(!_navResolutionMode, NavResolutionModeActivated());

        if (vars.currentStateId == NO_ALLOCATION_STATE_ID) {
            vars.enterStateId = _targetStateId;
        } else {
            vars.enterStateId = vars.currentStateId;
            vars.stateToNavBeforeEnter = stateNav(vars.currentStateId);
        }

        vars.enterStateBitmask = _stateBitmasks[vars.enterStateId];

        if (amounts.length > 0) {
            _takeFundsFromAgent(amounts);
        }

        if (vars.enterStateBitmask.isTargetState()) {
            _enterTarget();
        } else {
            _enterState(vars.enterStateId);
        }

        vars.stateToNavAfterEnter = stateNav(vars.enterStateId);
        require(
            vars.stateToNavAfterEnter > vars.stateToNavBeforeEnter + minNavDelta,
            SlippageCheckFailed(vars.stateToNavBeforeEnter, vars.stateToNavAfterEnter, minNavDelta)
        );

        if (vars.currentStateId != vars.enterStateId) {
            _currentStateId = vars.enterStateId;
            emit StateUpdated(vars.currentStateId, vars.enterStateId, vars.enterStateBitmask);
        }

        if (needPrepareForAgent) {
            (vars.remainingAmounts, vars.hasRemainder) = _prepareFundsAfterEnter();
        }

        emit Entered(vars.stateToNavBeforeEnter, vars.stateToNavAfterEnter, vars.hasRemainder);

        return vars;
    }

    function _enterToState(bytes32 toStateId, uint256 minNavDelta) private {
        EnterToStateLocalVars memory vars;

        require(toStateId != NO_ALLOCATION_STATE_ID, Errors.IncorrectInput());
        require(_stateIds.contains(toStateId), StateNotFound(toStateId));

        vars.currentStateId = _currentStateId;
        vars.currentStateBitmask = _stateBitmasks[vars.currentStateId];
        vars.toStateBitmask = _stateBitmasks[toStateId];

        require(vars.toStateBitmask != 0, Errors.ZeroAmount());
        require(vars.toStateBitmask.height() >= vars.currentStateBitmask.height(), Errors.IncorrectInput());

        if (vars.currentStateId != toStateId) {
            _currentStateId = toStateId;
        }

        vars.stateToNavBeforeEnter = stateNav(toStateId);

        if (vars.toStateBitmask.isTargetState()) {
            _enterTarget();
        } else {
            _enterState(toStateId);
        }

        vars.stateToNavAfterEnter = stateNav(toStateId);

        require(
            vars.stateToNavAfterEnter > vars.stateToNavBeforeEnter + minNavDelta,
            SlippageCheckFailed(vars.stateToNavBeforeEnter, vars.stateToNavAfterEnter, minNavDelta)
        );

        emit ReenteredToState(toStateId);
    }

    /* Emergency functions */

    function acceptNav(bytes32 acceptedStateId) public onlyEmergencyManager returns (uint256) {
        require(_navResolutionMode, NavResolutionModeNotActivated());
        _setCurrentStateId(acceptedStateId);
        _setNavResolutionMode(false);
        uint256 nav = stateNav(acceptedStateId);
        IStrategyContainer(_strategyContainer).resolveStrategyNav(nav);
        return nav;
    }

    function _setNavResolutionMode(bool navResolutionModeUpdated) private {
        if (navResolutionModeUpdated != _navResolutionMode) {
            _navResolutionMode = navResolutionModeUpdated;
            emit NavResolutionModeUpdated(navResolutionModeUpdated);
        }
    }

    function _setCurrentStateId(bytes32 stateId) private {
        require(_stateIds.contains(stateId), StateNotFound(stateId));
        bytes32 oldStateId = _currentStateId;
        if (stateId != oldStateId) {
            _currentStateId = stateId;
            emit StateUpdated(oldStateId, stateId, _stateBitmasks[stateId]);
        }
    }

    /*
    Allow to:
    1. Exit from target state
    2. Exit from intermediate state
    3. Withdraw tokens proportionally to share
    */
    function exit(
        uint256 share,
        uint256 maxNavDelta
    ) external payable onlyStrategyContainer nonReentrant returns (address[] memory, uint256[] memory) {
        require(share > 0 && share <= BPS, Errors.IncorrectAmount());
        require(!_navResolutionMode, NavResolutionModeActivated());

        ExitLocalVars memory vars;
        vars.currentStateId = _currentStateId;
        vars.currentStateBitmask = _stateBitmasks[vars.currentStateId];
        vars.outputTokens = _outputTokens.values();
        vars.currentStateNavBeforeExit = stateNav(vars.currentStateId);
        vars.amountsBeforeExit = _tokensAmountsDump(vars.outputTokens, BPS);
        require(vars.currentStateId != NO_ALLOCATION_STATE_ID, ExitUnavailable());

        if (share == BPS) {
            _currentStateId = NO_ALLOCATION_STATE_ID;
        }

        if (vars.currentStateBitmask.isProtocolState()) {
            if (vars.currentStateBitmask.isTargetState()) {
                _exitTarget(share);
            } else {
                _exitFromState(vars.currentStateId, share);
            }
            vars.tokenShare = vars.currentStateBitmask.isTokenState() ? share : BPS;
        } else {
            vars.tokenShare = share;
        }
        vars.currentStateNavAfterExit = stateNav(vars.currentStateId);
        (vars.outputAmounts, vars.hasRemainder) = _prepareFundsAfterExit(vars.amountsBeforeExit, vars.tokenShare);
        require(
            vars.currentStateNavBeforeExit <= vars.currentStateNavAfterExit + maxNavDelta,
            SlippageCheckFailed(vars.currentStateNavBeforeExit, vars.currentStateNavAfterExit, maxNavDelta)
        );
        emit Exited(vars.currentStateNavBeforeExit, vars.currentStateNavAfterExit, vars.currentStateId);
        return (vars.outputTokens, vars.outputAmounts);
    }

    function harvest() external payable onlyStrategyContainerOrHarvestManager nonReentrant returns (uint256) {
        require(!_navResolutionMode, NavResolutionModeActivated());
        HarvestLocalVars memory vars;

        vars.currentStateId = _currentStateId;
        if (vars.currentStateId == NO_ALLOCATION_STATE_ID) {
            return 0;
        }
        vars.currentStateBitmask = _stateBitmasks[vars.currentStateId];
        vars.treasury = IStrategyContainer(_strategyContainer).treasury();
        vars.feePct = IStrategyContainer(_strategyContainer).feePct();

        require(vars.treasury != address(0), Errors.ZeroAddress());

        _harvest(vars.currentStateId, vars.treasury, vars.feePct);
        vars.currentStateNav = stateNav(vars.currentStateId);
        emit Harvested(vars.currentStateId, vars.currentStateNav);
        return vars.currentStateNav;
    }

    function emergencyExit(
        bytes32 toStateId,
        uint256 share
    ) public payable override onlyStrategyContainerOrEmergencyManager nonReentrant {
        require(share > 0 && share <= BPS, Errors.IncorrectAmount());
        require(_stateIds.contains(toStateId), StateNotFound(toStateId));

        EmergencyExitLocalVars memory vars;
        vars.currentStateId = _currentStateId;
        vars.currentStateBitmask = _stateBitmasks[vars.currentStateId];
        vars.toStateBitmask = _stateBitmasks[toStateId];
        vars.isResolvingEmergency = IStrategyContainer(_strategyContainer).isResolvingEmergency();

        require(vars.toStateBitmask != 0, Errors.ZeroAmount());
        require(vars.toStateBitmask.height() <= vars.currentStateBitmask.height(), Errors.IncorrectInput());

        if (!vars.isResolvingEmergency) {
            IStrategyContainer(_strategyContainer).startEmergencyResolution();
        }
        if (!_navResolutionMode) {
            _setNavResolutionMode(true);
        }
        bytes memory returnData;
        (vars.isExitSuccess, returnData) = address(this).call(
            abi.encodeWithSelector(this.tryEmergencyExit.selector, toStateId, share)
        );
        // Silently ignore return data - emergency exit failure is handled by isExitSuccess flag
        if (vars.isExitSuccess) {
            emit EmergencyExitSucceeded(toStateId);
        } else {
            emit EmergencyExitFailed(toStateId);
        }
    }

    function emergencyExitMultiple(
        bytes32[] calldata toStateIds,
        uint256[] calldata shares
    ) external payable override onlyStrategyContainerOrEmergencyManager {
        require(toStateIds.length == shares.length, Errors.ArrayLengthMismatch());
        for (uint256 i = 0; i < toStateIds.length; ) {
            emergencyExit(toStateIds[i], shares[i]);
            unchecked {
                ++i;
            }
        }
    }

    function tryEmergencyExit(bytes32 toStateId, uint256 share) external {
        require(msg.sender == address(this), Errors.Unauthorized());
        _emergencyExit(toStateId, share);
    }

    /* Helper functions */

    function getTokenAmountInNotion(address token, uint256 amount) public view returns (uint256) {
        address priceOracleCached = IStrategyContainer(_strategyContainer).priceOracle();
        require(priceOracleCached != address(0), Errors.ZeroAddress());
        return IPriceOracleAggregator(priceOracleCached).getRelativeValueUnified(token, _notion, amount);
    }

    function _takeFundsFromAgent(uint256[] memory amounts) private {
        uint256 length = _inputTokens.length();
        require(amounts.length == length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; ) {
            if (amounts[i] > 0) {
                IERC20(_inputTokens.at(i)).safeTransferFrom(_strategyContainer, address(this), amounts[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    function _prepareFundsAfterEnter() private returns (uint256[] memory, bool) {
        PrepareFundsAfterEnterLocalVars memory vars;

        vars.tokens = _inputTokens.values();
        vars.length = vars.tokens.length;
        vars.amounts = new uint256[](vars.length);
        vars.container = _strategyContainer;

        for (uint256 i = 0; i < vars.length; ) {
            uint256 balance = IERC20(vars.tokens[i]).balanceOf(address(this));

            if (balance > 0) {
                IERC20(vars.tokens[i]).forceApprove(vars.container, balance);
                vars.amounts[i] = balance;
            }

            if (balance > 0 && !vars.hasRemainder) {
                vars.hasRemainder = true;
            }
            unchecked {
                ++i;
            }
        }
        return (vars.amounts, vars.hasRemainder);
    }

    function _prepareFundsAfterExit(
        uint256[] memory amountsBeforeExit,
        uint256 share
    ) private returns (uint256[] memory, bool) {
        PrepareFundsAfterExitLocalVars memory vars;

        vars.outputTokens = _outputTokens.values();
        vars.length = vars.outputTokens.length;
        vars.outputAmounts = new uint256[](vars.length);
        vars.container = _strategyContainer;

        require(vars.length == amountsBeforeExit.length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < vars.length; ) {
            uint256 delta = IERC20(vars.outputTokens[i]).balanceOf(address(this)) - amountsBeforeExit[i];
            uint256 amount = delta + amountsBeforeExit[i].mulDiv(share, BPS);
            if (amount > 0) {
                IERC20(vars.outputTokens[i]).forceApprove(vars.container, amount);
                vars.outputAmounts[i] = amount;
            }

            if (vars.outputAmounts[i] > 0 && !vars.hasRemainder) {
                vars.hasRemainder = true;
            }
            unchecked {
                ++i;
            }
        }
        return (vars.outputAmounts, vars.hasRemainder);
    }

    function _tokensAmountsDump(address[] memory tokens, uint256 share) private view returns (uint256[] memory) {
        uint256 length = tokens.length;
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (share < BPS) {
                    amounts[i] = balance.mulDiv(share, BPS);
                } else {
                    amounts[i] = balance;
                }
            }
            unchecked {
                ++i;
            }
        }
        return amounts;
    }

    function _swapToInputTokens(
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        bool mustSucceed
    ) internal virtual {
        require(_inputTokens.contains(tokenOut), Errors.Unauthorized());
        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }
        address swapRouter = IContainer(_strategyContainer).swapRouter();
        IERC20(tokenIn).forceApprove(swapRouter, amountIn);
        (bool success, ) = ISwapRouter(swapRouter).tryPredefinedSwap(tokenIn, tokenOut, amountIn, minAmountOut);
        if (mustSucceed && !success) revert Errors.SwapFailed(tokenIn, tokenOut, amountIn, minAmountOut);
    }

    function _enterTarget() internal virtual;

    function _enterState(bytes32 stateId) internal virtual;

    function _exitTarget(uint256 share) internal virtual;
    function _exitFromState(bytes32 stateId, uint256 share) internal virtual;
    function _emergencyExit(bytes32 toStateId, uint256 share) internal virtual;

    function _harvest(bytes32 _stateId, address _treasury, uint256 _feePct) internal virtual {}
}
