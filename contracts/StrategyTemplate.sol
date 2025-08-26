// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyContainer} from "./interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "./interfaces/IStrategyTemplate.sol";
import {IContainer} from "./interfaces/IContainer.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract StrategyTemplate is Initializable, IStrategyTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 internal constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    address private _containerAgent;
    uint256 internal constant BPS = 10_000;
    bytes32 private constant ZERO_STATE_ID = bytes32(0);

    address[] private _inputTokens;
    address[] private _outputTokens;

    bytes32 private _stateIdAfterEmergencyExit;

    mapping(bytes32 => bool) private _isOnlyTokenState;

    modifier notInEmergencyMode() {
        require(_stateIdAfterEmergencyExit == ZERO_STATE_ID, EmergencyModeEnabled());
        _;
    }

    modifier onlyContainerAgent() {
        require(msg.sender == _containerAgent, Errors.Unauthorized());
        _;
    }

    modifier onlyEmergencyManager() {
        require(
            AccessControlUpgradeable(_containerAgent).hasRole(EMERGENCY_MANAGER_ROLE, msg.sender),
            Errors.Unauthorized()
        );
        _;
    }

    function inputTokens() external view returns (address[] memory) {
        return _inputTokens;
    }

    function outputTokens() external view returns (address[] memory) {
        return _outputTokens;
    }

    function initialize(address containerAgent) public virtual;

    function __StrategyTemplate_init(
        address[] memory __inputTokens,
        address[] memory __outputTokens,
        address containerAgent
    ) internal onlyInitializing {
        require(containerAgent != address(0), Errors.ZeroAddress());
        require(__inputTokens.length > 0, Errors.ZeroAmount());
        require(__outputTokens.length > 0, Errors.ZeroAmount());

        _containerAgent = containerAgent;
        _registerStates();
        for (uint256 i = 0; i < __inputTokens.length; i++) {
            require(__inputTokens[i] != address(0), Errors.ZeroAddress());
            _inputTokens.push(__inputTokens[i]);
        }
        for (uint256 i = 0; i < __outputTokens.length; i++) {
            require(__outputTokens[i] != address(0), Errors.ZeroAddress());
            _outputTokens.push(__outputTokens[i]);
        }
    }

    function _registerStates() internal virtual;

    function _setOnlyTokenState(bytes32 stateId) internal {
        _isOnlyTokenState[stateId] = true;
    }

    function enter(
        uint256[] calldata amounts,
        uint256 minNavDelta
    ) public payable override notInEmergencyMode onlyContainerAgent returns (uint256, bool, uint256[] memory) {
        EnterLocalVars memory vars;

        _takeFundsFromAgent(amounts);

        vars.allocatedNavBeforeEnter = nav();
        _enter();
        vars.allocatedNavAfterEnter = nav();

        require(
            vars.allocatedNavAfterEnter - vars.allocatedNavBeforeEnter > minNavDelta,
            SlippageCheckFailed(vars.allocatedNavBeforeEnter, vars.allocatedNavAfterEnter)
        );

        (vars.remainingAmounts, vars.hasRemainder) = _prepareFundsAfterEnter(_inputTokens);

        emit Entered(vars.allocatedNavBeforeEnter, vars.allocatedNavAfterEnter, vars.hasRemainder);
        return (vars.allocatedNavAfterEnter, vars.hasRemainder, vars.remainingAmounts);
    }

    function reenterAfterEmergencyExit(uint256 minNavDelta) public payable override onlyEmergencyManager {
        ReenterAfterEmergencyExitLocalVars memory vars;
        vars.currentStateId = _stateIdAfterEmergencyExit;

        require(vars.currentStateId != ZERO_STATE_ID, EmergencyModeDisabled());

        _stateIdAfterEmergencyExit = ZERO_STATE_ID;

        vars.allocatedNavBeforeEnter = nav();
        _enter();
        vars.allocatedNavAfterEnter = nav();

        require(
            vars.allocatedNavAfterEnter - vars.allocatedNavBeforeEnter >= minNavDelta,
            SlippageCheckFailed(vars.allocatedNavBeforeEnter, vars.allocatedNavAfterEnter)
        );

        emit Entered(vars.allocatedNavBeforeEnter, vars.allocatedNavAfterEnter, false);
    }

    function exit(
        uint256 share,
        uint256 minNavDelta
    ) public payable override onlyContainerAgent returns (address[] memory, uint256[] memory) {
        require(share > 0, Errors.ZeroAmount());

        ExitLocalVars memory vars;

        vars.currentStateId = _stateIdAfterEmergencyExit;
        vars.outputTokens = _outputTokens;
        if (vars.currentStateId != bytes32(0)) {
            vars.isOnlyTokenState = _isOnlyTokenState[vars.currentStateId];
        }

        uint256 outputTokensLength = vars.outputTokens.length;
        vars.amountsBeforeExit = new uint256[](outputTokensLength);

        for (uint256 i = 0; i < outputTokensLength; i++) {
            address token = vars.outputTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (token == address(0) || balance == 0) {
                continue;
            }
            vars.amountsBeforeExit[i] = balance;
        }

        if (!vars.isOnlyTokenState) {
            vars.allocatedNavBeforeExit = allocatedNav(vars.currentStateId);
            _exit(share, vars.currentStateId);
            vars.allocatedNavAfterExit = allocatedNav(vars.currentStateId);
            require(
                vars.allocatedNavBeforeExit - vars.allocatedNavAfterExit > minNavDelta,
                SlippageCheckFailed(vars.allocatedNavBeforeExit, vars.allocatedNavAfterExit)
            );
        }
        (vars.remainingAmounts, ) = _prepareFundsAfterExit(vars.outputTokens, vars.amountsBeforeExit, share);
        emit Exited(vars.allocatedNavBeforeExit, vars.allocatedNavAfterExit, vars.currentStateId);
        return (vars.outputTokens, vars.remainingAmounts);
    }
    function harvest() public payable override onlyContainerAgent returns (uint256) {
        _claimAndSwapRewards(IContainer(_containerAgent).swapRouter());
        _takeFees();
        _enter();
        uint256 navAfter = nav();
        emit Harvested(navAfter);
        return navAfter;
    }

    function emergencyExit(bytes32 toStateId) public payable override onlyEmergencyManager {
        _emergencyExit(toStateId);
        _stateIdAfterEmergencyExit = toStateId;
        emit EmergencyExited(toStateId);
    }

    function nav() public view virtual override returns (uint256) {
        return allocatedNav(bytes32(0));
    }

    function allocatedNav(bytes32 stateId) public view virtual override returns (uint256);

    function _enter() internal virtual {}

    function _exit(uint256 share, bytes32 stateId) internal virtual {}

    function _emergencyExit(bytes32 toStateId) internal virtual {}

    function _claimAndSwapRewards(address swapRouter) internal virtual {}

    function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
        address priceOracle = _getPriceOracle();
        return IPriceOracle(priceOracle).getUsdValue(token, amount);
    }

    function _getPriceOracle() internal view returns (address) {
        address priceOracle = IStrategyContainer(_containerAgent).priceOracle();
        require(priceOracle != address(0), Errors.ZeroAddress());
        return priceOracle;
    }

    function _getSwapRouter() internal view returns (address) {
        address swapRouter = IContainer(_containerAgent).swapRouter();
        require(swapRouter != address(0), Errors.ZeroAddress());
        return swapRouter;
    }

    function _getTreasury() internal view returns (address) {
        address treasury = IStrategyContainer(_containerAgent).treasury();
        require(treasury != address(0), Errors.ZeroAddress());
        return treasury;
    }

    function _takeFees() private {
        TakeFeesLocalVars memory vars;

        vars.treasury = _getTreasury();
        vars.feePct = IStrategyContainer(_containerAgent).feePct();

        vars.lengthCached = _inputTokens.length;
        vars.inputTokens = _inputTokens;

        if (vars.treasury == address(0) || vars.feePct == 0) {
            return;
        }

        for (uint256 i = 0; i < vars.lengthCached; i++) {
            address token = vars.inputTokens[i];
            if (token == address(0)) {
                continue;
            }
            uint256 feeSize;
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                feeSize = balance.mulDiv(vars.feePct, BPS);
            } else {
                continue;
            }

            if (feeSize > 0) {
                IERC20(token).safeTransfer(vars.treasury, feeSize);
            }
        }
    }

    function _takeFundsFromAgent(uint256[] calldata amounts) private {
        uint256 length = _inputTokens.length;

        require(_containerAgent != address(0), Errors.ZeroAddress());
        require(amounts.length == length, Errors.ArrayLengthMismatch());

        for (uint256 i = 0; i < length; i++) {
            address token = _inputTokens[i];
            if (token == address(0)) {
                continue;
            }
            if (amounts[i] > 0) {
                IERC20(token).safeTransferFrom(_containerAgent, address(this), amounts[i]);
            }
        }
    }

    function _prepareFundsAfterExit(
        address[] memory tokens,
        uint256[] memory amountsBeforeExit,
        uint256 share
    ) private returns (uint256[] memory, bool) {
        uint256 length = tokens.length;
        bool hasRemainder;

        uint256[] memory amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 delta = IERC20(tokens[i]).balanceOf(address(this)) - amountsBeforeExit[i];
            uint256 amountForApprove = delta + amountsBeforeExit[i].mulDiv(share, BPS);
            if (amountForApprove > 0) {
                IERC20(tokens[i]).forceApprove(_containerAgent, amountForApprove);
                amounts[i] = amountForApprove;
            }

            if (amountForApprove > 0 && !hasRemainder) {
                hasRemainder = true;
            }
        }
        return (amounts, hasRemainder);
    }

    function _prepareFundsAfterEnter(address[] memory tokens) private returns (uint256[] memory, bool) {
        bool hasRemainder;
        uint256 length = tokens.length;
        uint256[] memory amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));

            if (balance > 0) {
                IERC20(tokens[i]).forceApprove(_containerAgent, balance);
                amounts[i] = balance;
            }

            if (balance > 0 && !hasRemainder) {
                hasRemainder = true;
            }
        }
        return (amounts, hasRemainder);
    }
}
