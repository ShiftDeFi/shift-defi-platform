// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IContainerPrincipal} from "./interfaces/IContainerPrincipal.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IReshufflingGateway} from "./interfaces/IReshufflingGateway.sol";
import {EnumerableAddressSetExtended} from "./libraries/helpers/EnumerableAddressSetExtended.sol";
import {Errors} from "./libraries/helpers/Errors.sol";

contract Vault is IVault, Initializable, AccessControlUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableAddressSetExtended for EnumerableSet.AddressSet;
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 private constant CONTAINER_MANAGER_ROLE = keccak256("CONTAINER_MANAGER_ROLE");
    bytes32 private constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 private constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    uint256 private constant MAX_CONTAINERS = 256;
    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant DEAD_SHARES = 1000;

    VaultStatus public status;

    uint256 public maxDepositAmount;
    uint256 public minDepositAmount;
    uint256 public maxDepositBatchSize;
    uint256 public minDepositBatchSize;
    uint256 public minWithdrawBatchRatio;

    IERC20 public notion;

    uint256 public depositBatchId;
    uint256 public lastResolvedDepositBatchId;
    uint256 public bufferedDeposits;
    mapping(uint256 => mapping(address => uint256)) public pendingBatchDeposits;
    mapping(uint256 => uint256) public depositBatchTotalNotion;
    mapping(uint256 => uint256) public depositBatchTotalShares;
    mapping(uint256 => uint256) public batchNotionRemainder;
    uint256 public totalUnclaimedNotionRemainder;

    mapping(address => ContainerReport) private _depositReports;
    uint256 private _depositReportBitmask;

    uint256 public withdrawBatchId;
    uint256 public lastResolvedWithdrawBatchId;
    uint256 public bufferedSharesToWithdraw;
    mapping(uint256 => mapping(address => uint256)) public pendingBatchWithdrawals;
    mapping(uint256 => uint256) public withdrawBatchTotalShares;
    mapping(uint256 => uint256) public withdrawBatchTotalNotion;
    uint256 public totalUnclaimedNotionForWithdraw;

    uint256 private _withdrawReportBitmask;

    EnumerableSet.AddressSet private _containers;
    mapping(address => uint256) public containerWeights;

    address public reshufflingGateway;
    bool public isReshuffling;
    bool public isRepairing;

    mapping(address => bool) private _hasClaimedReshufflingGateway;

    modifier onlyContainer() {
        require(_isContainer(msg.sender), NotContainer());
        _;
    }

    modifier notInRepairingMode() {
        require(!isRepairing, VaultIsInRepairingMode());
        _;
    }

    modifier notInReshufflingMode() {
        require(!isReshuffling, VaultIsInReshufflingMode());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Vault contract with initial configuration.
     * @param _name The name of the ERC20 token representing Vault shares
     * @param _symbol The symbol of the ERC20 token representing Vault shares
     * @param _notion The address of the NOTION token contract
     * @param roleAddresses Struct containing addresses for protocol roles
     * @param limits Struct containing operational limits
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _notion,
        RoleAddresses calldata roleAddresses,
        Limits calldata limits
    ) public initializer {
        __AccessControl_init();
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();

        require(roleAddresses.defaultAdmin != address(0), Errors.ZeroAddress());
        require(roleAddresses.containerManager != address(0), Errors.ZeroAddress());
        require(roleAddresses.operator != address(0), Errors.ZeroAddress());
        require(roleAddresses.configurator != address(0), Errors.ZeroAddress());
        require(roleAddresses.emergencyManager != address(0), Errors.ZeroAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, roleAddresses.defaultAdmin);
        _grantRole(CONTAINER_MANAGER_ROLE, roleAddresses.containerManager);
        _grantRole(OPERATOR_ROLE, roleAddresses.operator);
        _grantRole(CONFIGURATOR_ROLE, roleAddresses.configurator);
        _grantRole(EMERGENCY_MANAGER_ROLE, roleAddresses.emergencyManager);

        _setMaxDepositBatchSize(limits.maxDepositBatchSize);
        _setMaxDepositAmount(limits.maxDepositAmount);
        _setMinDepositAmount(limits.minDepositAmount);
        _setMinDepositBatchSize(limits.minDepositBatchSize);
        _setMinWithdrawBatchRatio(limits.minWithdrawBatchRatio);

        require(_notion != address(0), Errors.ZeroAddress());
        notion = IERC20(_notion);
    }

    // ---- Vault Configuration ----

    function setReshufflingGateway(address _reshufflingGateway) external onlyRole(EMERGENCY_MANAGER_ROLE) {
        require(_reshufflingGateway != address(0), Errors.ZeroAddress());
        address previousGateway = reshufflingGateway;
        reshufflingGateway = _reshufflingGateway;
        emit ReshufflingGatewayUpdated(previousGateway, _reshufflingGateway);
    }

    function setReshufflingMode(bool _isReshuffling) external onlyRole(EMERGENCY_MANAGER_ROLE) {
        require(reshufflingGateway != address(0), ReshufflingGatewayNotSet());
        require(isReshuffling != _isReshuffling, Errors.IncorrectInput());
        isReshuffling = _isReshuffling;
        emit ReshufflingModeUpdated(_isReshuffling);
    }

    function activateRepairingMode() external onlyRole(EMERGENCY_MANAGER_ROLE) notInRepairingMode {
        require(reshufflingGateway != address(0), ReshufflingGatewayNotSet());
        isRepairing = true;
        emit RepairingModeSet();
    }

    function setMaxDepositAmount(uint256 _maxDepositAmount) external onlyRole(CONFIGURATOR_ROLE) {
        _setMaxDepositAmount(_maxDepositAmount);
    }

    function setMinDepositAmount(uint256 _minDepositAmount) external onlyRole(CONFIGURATOR_ROLE) {
        _setMinDepositAmount(_minDepositAmount);
    }

    function setMaxDepositBatchSize(uint256 _maxDepositBatchSize) external onlyRole(CONFIGURATOR_ROLE) {
        _setMaxDepositBatchSize(_maxDepositBatchSize);
    }

    function setMinDepositBatchSize(uint256 _minDepositBatchSize) external onlyRole(CONFIGURATOR_ROLE) {
        _setMinDepositBatchSize(_minDepositBatchSize);
    }

    function setMinWithdrawBatchRatio(uint256 _minWithdrawBatchRatio) external onlyRole(CONFIGURATOR_ROLE) {
        _setMinWithdrawBatchRatio(_minWithdrawBatchRatio);
    }

    function _setMaxDepositAmount(uint256 _maxDepositAmount) internal {
        require(
            _maxDepositAmount > minDepositAmount && _maxDepositAmount <= maxDepositBatchSize,
            Errors.IncorrectAmount()
        );
        maxDepositAmount = _maxDepositAmount;
        emit MaxDepositAmountUpdated(_maxDepositAmount);
    }

    function _setMinDepositAmount(uint256 _minDepositAmount) internal {
        require(_minDepositAmount > 0 && _minDepositAmount < maxDepositAmount, Errors.IncorrectAmount());
        minDepositAmount = _minDepositAmount;
        emit MinDepositAmountUpdated(_minDepositAmount);
    }

    function _setMaxDepositBatchSize(uint256 _maxDepositBatchSize) internal {
        require(_maxDepositBatchSize > minDepositBatchSize, Errors.IncorrectAmount());
        maxDepositBatchSize = _maxDepositBatchSize;
        emit MaxDepositBatchSizeUpdated(_maxDepositBatchSize);
    }

    function _setMinDepositBatchSize(uint256 _minDepositBatchSize) internal {
        require(
            _minDepositBatchSize > minDepositAmount && _minDepositBatchSize < maxDepositBatchSize,
            Errors.IncorrectAmount()
        );
        minDepositBatchSize = _minDepositBatchSize;
        emit MinDepositBatchSizeUpdated(_minDepositBatchSize);
    }

    function _setMinWithdrawBatchRatio(uint256 _minWithdrawBatchRatio) internal {
        require(_minWithdrawBatchRatio > 0 && _minWithdrawBatchRatio < MAX_BPS, Errors.IncorrectAmount());
        minWithdrawBatchRatio = _minWithdrawBatchRatio;
        emit MinWithdrawBatchRatioUpdated(_minWithdrawBatchRatio);
    }

    // ---- Container Management ----

    function getContainers() external view override returns (address[] memory, uint256[] memory) {
        uint256 length = _containers.length();
        address[] memory containers = new address[](length);
        uint256[] memory weights = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            address container = _containers.at(i);
            containers[i] = container;
            weights[i] = containerWeights[container];
        }
        return (containers, weights);
    }

    function addContainer(address container) external nonReentrant onlyRole(CONTAINER_MANAGER_ROLE) {
        require(container != address(0), Errors.ZeroAddress());
        require(_containers.add(container), ContainerAlreadyExists());

        uint256 length = _containers.length();
        require(length <= MAX_CONTAINERS, MaxContainersReached());

        if (length == 1) {
            containerWeights[container] = MAX_BPS;
        }

        notion.approve(container, type(uint256).max);
        emit ContainerAdded(container);
    }

    function setContainerWeights(
        address[] calldata containers,
        uint256[] calldata weights
    ) external onlyRole(CONTAINER_MANAGER_ROLE) {
        require(status == VaultStatus.Idle, IncorrectStatus());
        uint256 length = containers.length;
        require(length == weights.length, Errors.ArrayLengthMismatch());

        uint256 newWeightSum = 0;
        uint256 previousWeightSum = 0;

        for (uint256 i = 0; i < length; ++i) {
            require(_isContainer(containers[i]), ContainerNotFound(containers[i]));
            newWeightSum += weights[i];
            previousWeightSum += containerWeights[containers[i]];

            containerWeights[containers[i]] = weights[i];
            if (weights[i] == 0) {
                notion.approve(containers[i], 0);
                _containers.remove(containers[i]);
                emit ContainerRemoved(containers[i]);
            }
        }

        // NOTE: Ignore weight invariant if the last container is being removed
        require(newWeightSum == previousWeightSum || _containers.length() == 0, IncorrectWeights(newWeightSum));
        emit ContainerWeightsUpdated(containers, weights);
    }

    function isContainer(address container) external view override returns (bool) {
        return _isContainer(container);
    }

    function _isContainer(address container) internal view returns (bool) {
        return _containers.contains(container);
    }

    // ---- User actions ----

    function deposit(uint256 amount, address onBehalfOf) external nonReentrant {
        _deposit(amount, onBehalfOf);
    }

    function depositWithPermit(
        uint256 amount,
        address onBehalfOf,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        IERC20Permit(address(notion)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(amount, onBehalfOf);
    }

    function _deposit(uint256 amount, address onBehalfOf) internal notInRepairingMode notInReshufflingMode {
        require(amount >= minDepositAmount && amount <= maxDepositAmount, Errors.IncorrectAmount());

        uint256 batchId = depositBatchId;
        uint256 totalBatchDepositAmount = bufferedDeposits + amount;

        require(totalBatchDepositAmount <= maxDepositBatchSize, DepositBatchCapReached());

        bufferedDeposits = totalBatchDepositAmount;
        pendingBatchDeposits[batchId][onBehalfOf] += amount;

        notion.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, onBehalfOf, batchId, amount);
    }

    function claimDeposit(uint256 batchId, address onBehalfOf) external nonReentrant {
        require(batchId <= lastResolvedDepositBatchId, IncorrectBatchId());
        require(onBehalfOf != address(0), Errors.ZeroAddress());

        ClaimDepositLocalVars memory vars;
        vars.depositAmount = pendingBatchDeposits[batchId][onBehalfOf];
        require(vars.depositAmount > 0, NothingToClaim());

        vars.batchTotalNotion = depositBatchTotalNotion[batchId];
        vars.batchTotalShares = depositBatchTotalShares[batchId];
        vars.batchNotionRemainder = batchNotionRemainder[batchId];

        vars.sharesToClaim = vars.depositAmount.mulDiv(vars.batchTotalShares, vars.batchTotalNotion);

        pendingBatchDeposits[batchId][onBehalfOf] = 0;
        depositBatchTotalNotion[batchId] = vars.batchTotalNotion - vars.depositAmount;
        depositBatchTotalShares[batchId] = vars.batchTotalShares - vars.sharesToClaim;

        if (vars.batchNotionRemainder > 0) {
            vars.notionToClaim = vars.depositAmount.mulDiv(vars.batchNotionRemainder, vars.batchTotalNotion);
            batchNotionRemainder[batchId] = vars.batchNotionRemainder - vars.notionToClaim;
            totalUnclaimedNotionRemainder -= vars.notionToClaim;
            require(_isNotionDecreaseAllowed(vars.notionToClaim), NotEnoughNotion());
        }

        if (vars.sharesToClaim > 0) {
            _transfer(address(this), onBehalfOf, vars.sharesToClaim);
        }

        if (vars.notionToClaim > 0) {
            notion.safeTransfer(onBehalfOf, vars.notionToClaim);
        }

        emit DepositClaimed(msg.sender, onBehalfOf, batchId, vars.sharesToClaim, vars.notionToClaim);
    }

    function withdraw(uint256 sharesPercent) external nonReentrant notInReshufflingMode {
        require(sharesPercent > 0 && sharesPercent <= MAX_BPS, Errors.IncorrectAmount());
        WithdrawLocalVars memory vars;

        vars.sharesToBurn = balanceOf(msg.sender).mulDiv(sharesPercent, MAX_BPS);
        require(vars.sharesToBurn > 0, NothingToWithdraw());

        vars.withdrawBatchIdCached = withdrawBatchId;

        pendingBatchWithdrawals[vars.withdrawBatchIdCached][msg.sender] += vars.sharesToBurn;
        bufferedSharesToWithdraw += vars.sharesToBurn;

        _transfer(msg.sender, address(this), vars.sharesToBurn);

        emit Withdraw(msg.sender, vars.withdrawBatchIdCached, vars.sharesToBurn);
    }

    function claimWithdraw(uint256 batchId, address onBehalfOf) external nonReentrant {
        require(batchId <= lastResolvedWithdrawBatchId, IncorrectBatchId());
        require(onBehalfOf != address(0), Errors.ZeroAddress());

        ClaimWithdrawLocalVars memory vars;
        vars.withdrawnShares = pendingBatchWithdrawals[batchId][onBehalfOf];
        vars.batchTotalShares = withdrawBatchTotalShares[batchId];
        vars.batchTotalNotion = withdrawBatchTotalNotion[batchId];

        vars.notionToClaim = vars.withdrawnShares.mulDiv(vars.batchTotalNotion, vars.batchTotalShares);
        require(vars.notionToClaim > 0, NothingToClaim());

        pendingBatchWithdrawals[batchId][onBehalfOf] = 0;
        withdrawBatchTotalShares[batchId] = vars.batchTotalShares - vars.withdrawnShares;
        withdrawBatchTotalNotion[batchId] = vars.batchTotalNotion - vars.notionToClaim;

        totalUnclaimedNotionForWithdraw -= vars.notionToClaim;
        require(_isNotionDecreaseAllowed(vars.notionToClaim), NotEnoughNotion());

        _burn(address(this), vars.withdrawnShares);
        notion.safeTransfer(onBehalfOf, vars.notionToClaim);

        emit WithdrawClaimed(msg.sender, onBehalfOf, batchId, vars.notionToClaim);
    }

    // TODO: Implement PAUSE LOGIC
    function claimReshufflingGateway(address account) external nonReentrant {
        require(isRepairing, NotInRepairingMode());
        require(!_hasClaimedReshufflingGateway[account], AlreadyClaimed());

        _hasClaimedReshufflingGateway[account] = true;

        IReshufflingGateway(reshufflingGateway).withdraw(account);
        emit ReshufflingGatewayClaimed(account);
    }

    function _isNotionDecreaseAllowed(uint256 amountToTransfer) internal view returns (bool) {
        return
            notion.balanceOf(address(this)) >=
            amountToTransfer + bufferedDeposits + totalUnclaimedNotionRemainder + totalUnclaimedNotionForWithdraw;
    }

    // ---- Deposit Batch Processing ----

    function isDepositReportComplete() public view returns (bool) {
        return _depositReportBitmask == (1 << _containers.length()) - 1;
    }

    function startDepositBatchProcessing() external onlyRole(OPERATOR_ROLE) notInRepairingMode notInReshufflingMode {
        require(status == VaultStatus.Idle, IncorrectStatus());

        DepositBatchProcessingLocalVars memory vars;
        vars.totalBatchDepositAmount = bufferedDeposits;

        require(vars.totalBatchDepositAmount >= minDepositBatchSize, DepositBatchSizeTooSmall());

        status = VaultStatus.DepositBatchProcessingStarted;
        vars.batchId = depositBatchId++;
        depositBatchTotalNotion[vars.batchId] = vars.totalBatchDepositAmount;
        bufferedDeposits = 0;

        vars.containersNumber = _containers.length();
        require(vars.containersNumber > 0, NoContainers());
        vars.lastContainerIndex = vars.containersNumber - 1;

        for (uint256 i = 0; i < vars.containersNumber; ++i) {
            address container = _containers.at(i);
            uint256 containerWeight = containerWeights[container];

            if (i == vars.lastContainerIndex) {
                // NOTE: Last container takes all division dust
                vars.containerAmount = vars.totalBatchDepositAmount - vars.distributedNotion;
            } else {
                vars.containerAmount = vars.totalBatchDepositAmount.mulDiv(containerWeight, MAX_BPS);
            }

            vars.distributedNotion += vars.containerAmount;
            IContainerPrincipal(container).registerDepositRequest(vars.containerAmount);
        }

        require(vars.distributedNotion == vars.totalBatchDepositAmount, IncorrectNotionDistribution());

        emit DepositBatchProcessingStarted(vars.batchId, vars.totalBatchDepositAmount);
    }

    function skipDepositBatch() external onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.Idle, IncorrectBatchStatus());
        uint256 bufferedDepositsCached = bufferedDeposits;
        require(bufferedDepositsCached < minDepositBatchSize, CannotSkipBatch());
        status = VaultStatus.DepositBatchProcessingFinished;
        emit DepositBatchSkipped(depositBatchId, bufferedDepositsCached);
    }

    function reportDeposit(ContainerReport calldata report, uint256 notionRemainder) external onlyContainer {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectStatus());
        require(report.nav1 >= report.nav0, IncorrectReport());

        (, uint256 containerIndex) = _containers.indexOf(msg.sender);
        uint256 mask = 1 << containerIndex;
        uint256 reportBitmask = _depositReportBitmask;

        require(reportBitmask & mask == 0, ContainerAlreadyReported());

        uint256 previousBatchId = depositBatchId - 1;

        _depositReportBitmask = reportBitmask | mask;
        _depositReports[msg.sender] = report;

        if (notionRemainder > 0) {
            batchNotionRemainder[previousBatchId] += notionRemainder;
            totalUnclaimedNotionRemainder += notionRemainder;
            notion.safeTransferFrom(msg.sender, address(this), notionRemainder);
        }

        emit DepositReportReceived(msg.sender, previousBatchId, report.nav0, report.nav1, notionRemainder);
    }

    function resolveDepositBatch() external onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectBatchStatus());
        require(isDepositReportComplete(), MissingContainerReport());

        ResolveDepositBatchLocalVars memory vars;
        status = VaultStatus.DepositBatchProcessingFinished;
        vars.previousBatchId = depositBatchId - 1;
        lastResolvedDepositBatchId = vars.previousBatchId;
        _depositReportBitmask = 0;

        vars.containersNumber = _containers.length();

        for (uint256 i = 0; i < vars.containersNumber; ++i) {
            address container = _containers.at(i);

            ContainerReport memory report = _depositReports[container];

            vars.totalNav0 += report.nav0;
            vars.totalNav1 += report.nav1;
        }

        if (totalSupply() == 0) {
            _mint(address(this), DEAD_SHARES);
        }

        // NOTE: totalNav1 >= totalNav0 is enforced in `reportDeposit()`
        vars.batchDeltaNav = vars.totalNav1 - vars.totalNav0;
        vars.batchShares = vars.batchDeltaNav.mulDiv(totalSupply() + 1, vars.totalNav0 + 1);

        depositBatchTotalShares[vars.previousBatchId] = vars.batchShares;

        if (vars.batchShares > 0) {
            _mint(address(this), vars.batchShares);
        }

        emit DepositBatchProcessingFinished(vars.previousBatchId, vars.batchShares, vars.batchDeltaNav, vars.totalNav1);
    }

    // ---- Withdraw Batch Processing ----

    function isWithdrawReportComplete() public view returns (bool) {
        return _withdrawReportBitmask == (1 << _containers.length()) - 1;
    }

    function startWithdrawBatchProcessing() external onlyRole(OPERATOR_ROLE) notInReshufflingMode {
        require(status == VaultStatus.DepositBatchProcessingFinished, IncorrectBatchStatus());
        WithdrawBatchProcessingLocalVars memory vars;

        vars.bufferedSharesToWithdrawCached = bufferedSharesToWithdraw;
        vars.batchSharesPercent = _calculateSharesPercent(vars.bufferedSharesToWithdrawCached);
        require(vars.batchSharesPercent >= minWithdrawBatchRatio, NotEnoughSharesWithdrawn());

        status = VaultStatus.WithdrawBatchProcessingStarted;
        vars.batchId = withdrawBatchId++;
        withdrawBatchTotalShares[vars.batchId] = vars.bufferedSharesToWithdrawCached;

        bufferedSharesToWithdraw = 0;
        uint256 length = _containers.length();
        for (uint256 i = 0; i < length; ++i) {
            IContainerPrincipal(_containers.at(i)).registerWithdrawRequest(vars.batchSharesPercent);
        }
        emit WithdrawBatchProcessingStarted(vars.batchId, vars.bufferedSharesToWithdrawCached, vars.batchSharesPercent);
    }

    function skipWithdrawBatch() external onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.DepositBatchProcessingFinished, IncorrectBatchStatus());
        uint256 bufferedSharesToWithdrawCached = bufferedSharesToWithdraw;
        uint256 batchSharesPercent = _calculateSharesPercent(bufferedSharesToWithdrawCached);
        require(batchSharesPercent < minWithdrawBatchRatio, CannotSkipBatch());
        status = VaultStatus.Idle;
        emit WithdrawBatchSkipped(withdrawBatchId, bufferedSharesToWithdrawCached);
    }

    function reportWithdraw(uint256 notionAmount) external onlyContainer {
        require(status == VaultStatus.WithdrawBatchProcessingStarted, IncorrectBatchStatus());
        require(notionAmount > 0, IncorrectReport());

        (, uint256 containerIndex) = _containers.indexOf(msg.sender);

        uint256 mask = 1 << containerIndex;
        uint256 reportBitmask = _withdrawReportBitmask;
        require(reportBitmask & mask == 0, ContainerAlreadyReported());

        _withdrawReportBitmask = reportBitmask | mask;
        uint256 previousBatchId = withdrawBatchId - 1;
        withdrawBatchTotalNotion[previousBatchId] += notionAmount;
        totalUnclaimedNotionForWithdraw += notionAmount;

        notion.safeTransferFrom(msg.sender, address(this), notionAmount);

        emit WithdrawReportReceived(msg.sender, previousBatchId, notionAmount);
    }

    function resolveWithdrawBatch() external onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.WithdrawBatchProcessingStarted, IncorrectBatchStatus());
        require(isWithdrawReportComplete(), MissingContainerReport());

        status = VaultStatus.Idle;
        uint256 previousBatchId = withdrawBatchId - 1;
        lastResolvedWithdrawBatchId = previousBatchId;
        _withdrawReportBitmask = 0;

        emit WithdrawBatchProcessingFinished(previousBatchId, withdrawBatchTotalNotion[previousBatchId]);
    }

    function _calculateSharesPercent(uint256 shares) internal view returns (uint256) {
        return shares.mulDiv(MAX_BPS, totalSupply());
    }
}
