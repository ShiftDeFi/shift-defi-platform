// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IContainer} from "./interfaces/IContainer.sol";
import {IContainerPrincipal} from "./interfaces/IContainerPrincipal.sol";
import {IVault} from "./interfaces/IVault.sol";

import {EnumerableAddressSetExtended} from "./libraries/EnumerableAddressSetExtended.sol";
import {Errors} from "./libraries/Errors.sol";

contract Vault is
    IVault,
    Initializable,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableAddressSetExtended for EnumerableSet.AddressSet;
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 private constant CONTAINER_MANAGER_ROLE = keccak256("CONTAINER_MANAGER_ROLE");
    bytes32 private constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 private constant RESHUFFLING_MANAGER_ROLE = keccak256("RESHUFFLING_MANAGER_ROLE");
    bytes32 private constant RESHUFFLING_EXECUTOR_ROLE = keccak256("RESHUFFLING_EXECUTOR_ROLE");
    bytes32 public constant EMERGENCY_PAUSER_ROLE = keccak256("EMERGENCY_PAUSER_ROLE");

    uint256 private constant MAX_CONTAINERS = 255;
    uint256 private constant TOTAL_CONTAINER_WEIGHT = 10_000;
    uint256 private constant MAX_BPS = 1e18;

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
    mapping(uint256 => address) public containerByChainId;

    address public reshufflingGateway;
    bool public isReshuffling;

    uint256 public lastResolvedDepositBatchBlock;
    uint256 public lastResolvedWithdrawBatchBlock;
    uint256 public forcedDepositThreshold;
    uint256 public forcedWithdrawThreshold;
    uint256 public forcedBatchBlockLimit;

    modifier onlyContainer() {
        require(_isContainer(msg.sender), NotContainer());
        _;
    }

    modifier notInReshufflingMode() {
        require(!isReshuffling, Errors.ReshufflingModeEnabled());
        _;
    }

    modifier onlyInReshufflingMode() {
        require(isReshuffling, Errors.ReshufflingModeDisabled());
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
        Limits calldata limits,
        uint256 _forcedDepositThreshold,
        uint256 _forcedWithdrawThreshold,
        uint256 _forcedBatchBlockLimit
    ) public initializer {
        __AccessControl_init();
        __ERC20_init(_name, _symbol);
        __Pausable_init();
        __ReentrancyGuard_init();

        require(roleAddresses.defaultAdmin != address(0), Errors.ZeroAddress());
        require(roleAddresses.containerManager != address(0), Errors.ZeroAddress());
        require(roleAddresses.operator != address(0), Errors.ZeroAddress());
        require(roleAddresses.configurator != address(0), Errors.ZeroAddress());
        require(roleAddresses.reshufflingManager != address(0), Errors.ZeroAddress());
        require(roleAddresses.reshufflingExecutor != address(0), Errors.ZeroAddress());
        require(roleAddresses.emergencyPauser != address(0), Errors.ZeroAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, roleAddresses.defaultAdmin);
        _grantRole(CONTAINER_MANAGER_ROLE, roleAddresses.containerManager);
        _grantRole(OPERATOR_ROLE, roleAddresses.operator);
        _grantRole(CONFIGURATOR_ROLE, roleAddresses.configurator);
        _grantRole(RESHUFFLING_MANAGER_ROLE, roleAddresses.reshufflingManager);
        _grantRole(RESHUFFLING_EXECUTOR_ROLE, roleAddresses.reshufflingExecutor);
        _grantRole(EMERGENCY_PAUSER_ROLE, roleAddresses.emergencyPauser);

        _setMaxDepositBatchSize(limits.maxDepositBatchSize);
        _setMaxDepositAmount(limits.maxDepositAmount);
        _setMinDepositAmount(limits.minDepositAmount);
        _setMinDepositBatchSize(limits.minDepositBatchSize);
        _setMinWithdrawBatchRatio(limits.minWithdrawBatchRatio);

        require(_notion != address(0), Errors.ZeroAddress());
        notion = IERC20(_notion);

        depositBatchId = 1;
        withdrawBatchId = 1;

        _setForcedDepositThreshold(_forcedDepositThreshold);
        _setForcedWithdrawThreshold(_forcedWithdrawThreshold);
        _setForcedBatchBlockLimit(_forcedBatchBlockLimit);

        lastResolvedDepositBatchBlock = block.number;
        lastResolvedWithdrawBatchBlock = block.number;

        isReshuffling = true;
    }

    // ---- Vault Configuration ----

    /// @inheritdoc IVault
    function setReshufflingGateway(
        address _reshufflingGateway
    ) external onlyRole(RESHUFFLING_MANAGER_ROLE) notInReshufflingMode {
        require(_reshufflingGateway != address(0), Errors.ZeroAddress());
        address previousGateway = reshufflingGateway;
        require(previousGateway != _reshufflingGateway, Errors.SettingSameValue());
        reshufflingGateway = _reshufflingGateway;
        emit ReshufflingGatewayUpdated(previousGateway, _reshufflingGateway);
    }

    /// @inheritdoc IVault
    function enableReshufflingMode() external onlyRole(RESHUFFLING_MANAGER_ROLE) notInReshufflingMode {
        require(reshufflingGateway != address(0), Errors.ReshufflingGatewayNotSet());
        require(status == VaultStatus.Idle, IncorrectVaultStatus(status));
        isReshuffling = true;
        emit ReshufflingModeEnabled();
    }

    /// @inheritdoc IVault
    function disableReshufflingMode() external onlyRole(RESHUFFLING_EXECUTOR_ROLE) onlyInReshufflingMode {
        for (uint256 i = 0; i < _containers.length(); ++i) {
            address container = _containers.at(i);
            require(containerWeights[container] > 0, ZeroContainerWeight(container));
        }

        isReshuffling = false;
        emit ReshufflingModeDisabled();
    }

    /// @inheritdoc IVault
    function setMaxDepositAmount(uint256 _maxDepositAmount) external onlyRole(CONFIGURATOR_ROLE) {
        _setMaxDepositAmount(_maxDepositAmount);
    }

    /// @inheritdoc IVault
    function setMinDepositAmount(uint256 _minDepositAmount) external onlyRole(CONFIGURATOR_ROLE) {
        _setMinDepositAmount(_minDepositAmount);
    }

    /// @inheritdoc IVault
    function setMaxDepositBatchSize(uint256 _maxDepositBatchSize) external onlyRole(CONFIGURATOR_ROLE) {
        _setMaxDepositBatchSize(_maxDepositBatchSize);
    }

    /// @inheritdoc IVault
    function setMinDepositBatchSize(uint256 _minDepositBatchSize) external onlyRole(CONFIGURATOR_ROLE) {
        _setMinDepositBatchSize(_minDepositBatchSize);
    }

    /// @inheritdoc IVault
    function setMinWithdrawBatchRatio(uint256 _minWithdrawBatchRatio) external onlyRole(CONFIGURATOR_ROLE) {
        _setMinWithdrawBatchRatio(_minWithdrawBatchRatio);
    }

    /// @inheritdoc IVault
    function setForcedDepositThreshold(uint256 _forcedDepositThreshold) external onlyRole(CONFIGURATOR_ROLE) {
        _setForcedDepositThreshold(_forcedDepositThreshold);
    }

    /// @inheritdoc IVault
    function setForcedWithdrawThreshold(uint256 _forcedWithdrawThreshold) external onlyRole(CONFIGURATOR_ROLE) {
        _setForcedWithdrawThreshold(_forcedWithdrawThreshold);
    }

    /// @inheritdoc IVault
    function setForcedBatchBlockLimit(uint256 _forcedBatchBlockLimit) external onlyRole(CONFIGURATOR_ROLE) {
        _setForcedBatchBlockLimit(_forcedBatchBlockLimit);
    }

    function _setMaxDepositAmount(uint256 _maxDepositAmount) internal {
        require(
            _maxDepositAmount >= minDepositAmount && _maxDepositAmount <= maxDepositBatchSize,
            IncorrectMaxDepositAmount()
        );
        maxDepositAmount = _maxDepositAmount;
        emit MaxDepositAmountUpdated(_maxDepositAmount);
    }

    function _setMinDepositAmount(uint256 _minDepositAmount) internal {
        require(_minDepositAmount > 0 && _minDepositAmount <= maxDepositAmount, IncorrectMinDepositAmount());
        minDepositAmount = _minDepositAmount;
        emit MinDepositAmountUpdated(_minDepositAmount);
    }

    function _setMaxDepositBatchSize(uint256 _maxDepositBatchSize) internal {
        require(
            _maxDepositBatchSize > minDepositBatchSize && _maxDepositBatchSize >= maxDepositAmount,
            IncorrectMaxDepositBatchSize()
        );
        maxDepositBatchSize = _maxDepositBatchSize;
        emit MaxDepositBatchSizeUpdated(_maxDepositBatchSize);
    }

    function _setMinDepositBatchSize(uint256 _minDepositBatchSize) internal {
        require(_minDepositBatchSize > 0 && _minDepositBatchSize < maxDepositBatchSize, IncorrectMinDepositBatchSize());
        minDepositBatchSize = _minDepositBatchSize;
        emit MinDepositBatchSizeUpdated(_minDepositBatchSize);
    }

    function _setMinWithdrawBatchRatio(uint256 _minWithdrawBatchRatio) internal {
        require(_minWithdrawBatchRatio > 0 && _minWithdrawBatchRatio <= MAX_BPS, IncorrectMinWithdrawBatchRatio());
        minWithdrawBatchRatio = _minWithdrawBatchRatio;
        emit MinWithdrawBatchRatioUpdated(_minWithdrawBatchRatio);
    }

    function _setForcedDepositThreshold(uint256 _forcedDepositThreshold) internal {
        require(
            _forcedDepositThreshold > 0 && _forcedDepositThreshold < maxDepositBatchSize,
            IncorrectForcedDepositThreshold()
        );
        uint256 previousForcedDepositThreshold = forcedDepositThreshold;
        forcedDepositThreshold = _forcedDepositThreshold;
        emit ForcedDepositThresholdUpdated(previousForcedDepositThreshold, _forcedDepositThreshold);
    }

    function _setForcedWithdrawThreshold(uint256 _forcedWithdrawThreshold) internal {
        require(_forcedWithdrawThreshold > 0, IncorrectForcedWithdrawThreshold());
        uint256 previousForcedWithdrawThreshold = forcedWithdrawThreshold;
        forcedWithdrawThreshold = _forcedWithdrawThreshold;
        emit ForcedWithdrawThresholdUpdated(previousForcedWithdrawThreshold, _forcedWithdrawThreshold);
    }

    function _setForcedBatchBlockLimit(uint256 _forcedBatchBlockLimit) internal {
        require(_forcedBatchBlockLimit > 0, IncorrectForcedBatchBlockLimit());
        uint256 previousForcedBatchBlockLimit = forcedBatchBlockLimit;
        forcedBatchBlockLimit = _forcedBatchBlockLimit;
        emit ForcedBatchBlockLimitUpdated(previousForcedBatchBlockLimit, _forcedBatchBlockLimit);
    }

    // ---- Container Management ----

    /// @inheritdoc IVault
    function getContainers() external view returns (address[] memory, uint256[] memory) {
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

    /// @inheritdoc IVault
    function addContainer(
        address container,
        uint256 chainId
    ) external nonReentrant onlyRole(CONTAINER_MANAGER_ROLE) onlyInReshufflingMode {
        require(status == VaultStatus.Idle, IncorrectVaultStatus(status));
        require(container != address(0), Errors.ZeroAddress());
        require(chainId > 0, Errors.IncorrectChainId(chainId));

        uint256 length = _containers.length();
        require(length < MAX_CONTAINERS, MaxContainersReached());

        address containerForChainId = containerByChainId[chainId];
        require(containerForChainId == address(0), ContainerForChainIdAlreadyExists(chainId, containerForChainId));
        containerByChainId[chainId] = container;

        if (chainId == block.chainid) {
            require(IContainer(container).containerType() == IContainer.ContainerType.Local, IncorrectContainerType());
        } else {
            require(
                IContainer(container).containerType() == IContainer.ContainerType.Principal,
                IncorrectContainerType()
            );
        }

        if (length == 0) {
            containerWeights[container] = TOTAL_CONTAINER_WEIGHT;
        }

        require(_containers.add(container), ContainerAlreadyExists());

        notion.forceApprove(container, type(uint256).max);
        emit ContainerAdded(container);
    }

    /// @inheritdoc IVault
    function setContainerWeights(
        address[] calldata containers,
        uint256[] calldata weights
    ) external onlyRole(CONTAINER_MANAGER_ROLE) onlyInReshufflingMode {
        require(status == VaultStatus.Idle, IncorrectVaultStatus(status));
        uint256 length = containers.length;
        require(length == weights.length, Errors.ArrayLengthMismatch());

        uint256 newWeightSum = 0;
        uint256 previousWeightSum = 0;
        uint256 minDepositBatchSizeCached = minDepositBatchSize;

        for (uint256 i = 1; i < length; ++i) {
            require(containers[i] > containers[i - 1], DuplicatingContainer(containers[i]));
        }

        for (uint256 i = 0; i < length; ++i) {
            require(_isContainer(containers[i]), ContainerNotFound(containers[i]));

            if (weights[i] > 0) {
                require(
                    minDepositBatchSizeCached.mulDiv(weights[i], TOTAL_CONTAINER_WEIGHT) > 0,
                    WeightRoundsToZero(containers[i], weights[i])
                );
            }
            newWeightSum += weights[i];
            previousWeightSum += containerWeights[containers[i]];

            containerWeights[containers[i]] = weights[i];
            if (weights[i] == 0) {
                notion.forceApprove(containers[i], 0);
                _containers.remove(containers[i]);
                if (IContainer(containers[i]).containerType() == IContainer.ContainerType.Local) {
                    delete containerByChainId[block.chainid];
                } else {
                    delete containerByChainId[IContainerPrincipal(containers[i]).remoteChainId()];
                }
                emit ContainerRemoved(containers[i]);
            }
        }

        // NOTE: Ignore weight invariant if the last container is being removed
        require(newWeightSum == previousWeightSum || _containers.length() == 0, IncorrectWeights(newWeightSum));
        emit ContainerWeightsUpdated(containers, weights);
    }

    /// @inheritdoc IVault
    function isContainer(address container) external view returns (bool) {
        return _isContainer(container);
    }

    function _isContainer(address container) internal view returns (bool) {
        return _containers.contains(container);
    }

    // ---- User actions ----

    /// @inheritdoc IVault
    function deposit(uint256 amount, address onBehalfOf) external whenNotPaused nonReentrant {
        _deposit(amount, onBehalfOf);
    }

    /// @inheritdoc IVault
    function depositWithPermit(
        uint256 amount,
        address onBehalfOf,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused nonReentrant {
        if (notion.allowance(msg.sender, address(this)) < amount) {
            IERC20Permit(address(notion)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        }
        _deposit(amount, onBehalfOf);
    }

    function _deposit(uint256 amount, address onBehalfOf) internal {
        require(onBehalfOf != address(0), Errors.ZeroAddress());
        require(amount >= minDepositAmount && amount <= maxDepositAmount, Errors.IncorrectAmount());

        uint256 batchId = depositBatchId;
        uint256 totalBatchDepositAmount = bufferedDeposits + amount;

        require(totalBatchDepositAmount <= maxDepositBatchSize, DepositBatchCapReached());

        bufferedDeposits = totalBatchDepositAmount;
        pendingBatchDeposits[batchId][onBehalfOf] += amount;

        notion.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, onBehalfOf, batchId, amount);
    }

    /// @inheritdoc IVault
    function claimDeposit(
        uint256 batchId,
        address onBehalfOf
    ) external whenNotPaused nonReentrant returns (uint256, uint256) {
        require(batchId <= lastResolvedDepositBatchId, IncorrectBatchId());
        require(onBehalfOf != address(0), Errors.ZeroAddress());

        ClaimDepositLocalVars memory vars;
        vars.depositAmount = pendingBatchDeposits[batchId][onBehalfOf];
        if (vars.depositAmount == 0) {
            return (0, 0);
        }

        vars.batchTotalNotion = depositBatchTotalNotion[batchId];
        vars.batchNotionRemainder = batchNotionRemainder[batchId];

        vars.sharesToClaim = vars.depositAmount.mulDiv(depositBatchTotalShares[batchId], vars.batchTotalNotion);

        pendingBatchDeposits[batchId][onBehalfOf] = 0;

        if (vars.batchNotionRemainder > 0) {
            vars.notionToClaim = vars.depositAmount.mulDiv(vars.batchNotionRemainder, vars.batchTotalNotion);
            totalUnclaimedNotionRemainder -= vars.notionToClaim;
            require(_isNotionDecreaseAllowed(vars.notionToClaim), NotEnoughNotion());
        }

        if (vars.sharesToClaim == 0 && vars.notionToClaim == 0) {
            return (0, 0);
        }

        if (vars.sharesToClaim > 0) {
            _transfer(address(this), onBehalfOf, vars.sharesToClaim);
        }

        if (vars.notionToClaim > 0) {
            notion.safeTransfer(onBehalfOf, vars.notionToClaim);
        }

        emit DepositClaimed(msg.sender, onBehalfOf, batchId, vars.sharesToClaim, vars.notionToClaim);
        return (vars.sharesToClaim, vars.notionToClaim);
    }

    /// @inheritdoc IVault
    function withdraw(uint256 sharesPercent) external whenNotPaused nonReentrant notInReshufflingMode {
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

    /// @inheritdoc IVault
    function claimWithdraw(uint256 batchId, address onBehalfOf) external whenNotPaused nonReentrant returns (uint256) {
        require(batchId <= lastResolvedWithdrawBatchId, IncorrectBatchId());
        require(onBehalfOf != address(0), Errors.ZeroAddress());

        ClaimWithdrawLocalVars memory vars;
        vars.withdrawnShares = pendingBatchWithdrawals[batchId][onBehalfOf];

        vars.notionToClaim = vars.withdrawnShares.mulDiv(
            withdrawBatchTotalNotion[batchId],
            withdrawBatchTotalShares[batchId]
        );
        if (vars.notionToClaim == 0) {
            return 0;
        }

        pendingBatchWithdrawals[batchId][onBehalfOf] = 0;

        totalUnclaimedNotionForWithdraw -= vars.notionToClaim;
        require(_isNotionDecreaseAllowed(vars.notionToClaim), NotEnoughNotion());

        _burn(address(this), vars.withdrawnShares);
        notion.safeTransfer(onBehalfOf, vars.notionToClaim);

        emit WithdrawClaimed(msg.sender, onBehalfOf, batchId, vars.notionToClaim);
        return vars.notionToClaim;
    }

    function _isNotionDecreaseAllowed(uint256 amountToTransfer) internal view returns (bool) {
        return
            notion.balanceOf(address(this)) >=
            amountToTransfer + bufferedDeposits + totalUnclaimedNotionRemainder + totalUnclaimedNotionForWithdraw;
    }

    // ---- Deposit Batch Processing ----

    /// @inheritdoc IVault
    function isDepositReportComplete() public view returns (bool) {
        return _depositReportBitmask == (1 << _containers.length()) - 1;
    }

    /// @inheritdoc IVault
    function startDepositBatchProcessing() external whenNotPaused onlyRole(OPERATOR_ROLE) notInReshufflingMode {
        require(status == VaultStatus.Idle, IncorrectVaultStatus(status));

        DepositBatchProcessingLocalVars memory vars;
        vars.totalBatchDepositAmount = bufferedDeposits;
        require(vars.totalBatchDepositAmount >= minDepositBatchSize, DepositBatchSizeTooSmall());

        vars.containersNumber = _containers.length();
        require(vars.containersNumber > 0, NoContainers());

        status = VaultStatus.DepositBatchProcessingStarted;
        vars.batchId = depositBatchId++;
        depositBatchTotalNotion[vars.batchId] = vars.totalBatchDepositAmount;
        bufferedDeposits = 0;

        vars.undistributedWeight = TOTAL_CONTAINER_WEIGHT;
        vars.undistributedNotionAmount = vars.totalBatchDepositAmount;

        for (uint256 i = 0; i < vars.containersNumber; ++i) {
            address container = _containers.at(i);
            uint256 containerWeight = containerWeights[container];
            require(containerWeight > 0, ZeroContainerWeight(container));

            vars.containerAmount = vars.undistributedNotionAmount.mulDiv(containerWeight, vars.undistributedWeight);
            require(vars.containerAmount > 0, IncorrectContainerAmount(container));

            vars.undistributedWeight -= containerWeight;
            vars.undistributedNotionAmount -= vars.containerAmount;

            IContainerPrincipal(container).registerDepositRequest(vars.containerAmount);
        }

        require(vars.undistributedNotionAmount == 0, IncorrectNotionDistribution());
        require(vars.undistributedWeight == 0, IncorrectWeights(vars.undistributedWeight));

        emit DepositBatchProcessingStarted(vars.batchId, vars.totalBatchDepositAmount);
    }

    /// @inheritdoc IVault
    function skipDepositBatch() external whenNotPaused onlyRole(OPERATOR_ROLE) notInReshufflingMode {
        require(status == VaultStatus.Idle, IncorrectVaultStatus(status));
        require(totalSupply() > 0, CannotSkipBatchInEmptyVault());
        uint256 bufferedDepositsCached = bufferedDeposits;
        require(bufferedDepositsCached < minDepositBatchSize, CannotSkipBatch());

        if (bufferedDepositsCached >= forcedDepositThreshold) {
            uint256 batchProcessingDelay = block.number - lastResolvedDepositBatchBlock;
            require(batchProcessingDelay < forcedBatchBlockLimit, CannotSkipForcedBatch());
        }

        status = VaultStatus.DepositBatchProcessingFinished;
        emit DepositBatchSkipped(depositBatchId, bufferedDepositsCached);
    }

    /// @inheritdoc IVault
    function reportDeposit(
        ContainerReport calldata report,
        uint256 notionRemainder
    ) external whenNotPaused onlyContainer {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectVaultStatus(status));
        require(report.nav1 >= report.nav0, IncorrectReport());

        (, uint256 containerIndex) = _containers.indexOf(msg.sender);
        uint256 mask = 1 << containerIndex;
        uint256 reportBitmask = _depositReportBitmask;

        require(reportBitmask & mask == 0, ContainerAlreadyReported(msg.sender));

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

    /// @inheritdoc IVault
    function resolveDepositBatch() external whenNotPaused onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectVaultStatus(status));
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

        // NOTE: totalNav1 >= totalNav0 is enforced in `reportDeposit()`
        vars.batchDeltaNav = vars.totalNav1 - vars.totalNav0;
        vars.totalSupplyCached = totalSupply();
        if (vars.totalNav0 == 0 || vars.totalSupplyCached == 0) {
            vars.batchShares = vars.batchDeltaNav;
        } else {
            vars.batchShares = vars.batchDeltaNav.mulDiv(vars.totalSupplyCached, vars.totalNav0);
        }

        depositBatchTotalShares[vars.previousBatchId] = vars.batchShares;

        if (vars.batchShares > 0) {
            _mint(address(this), vars.batchShares);
        }

        emit DepositBatchProcessingFinished(vars.previousBatchId, vars.batchShares, vars.batchDeltaNav, vars.totalNav1);
    }

    // ---- Withdraw Batch Processing ----

    /// @inheritdoc IVault
    function isWithdrawReportComplete() public view returns (bool) {
        return _withdrawReportBitmask == (1 << _containers.length()) - 1;
    }

    /// @inheritdoc IVault
    function startWithdrawBatchProcessing() external whenNotPaused onlyRole(OPERATOR_ROLE) notInReshufflingMode {
        require(status == VaultStatus.DepositBatchProcessingFinished, IncorrectVaultStatus(status));
        WithdrawBatchProcessingLocalVars memory vars;

        vars.bufferedSharesToWithdrawCached = bufferedSharesToWithdraw;
        vars.batchSharesPercent = _calculateSharesPercent(vars.bufferedSharesToWithdrawCached);
        require(vars.batchSharesPercent >= minWithdrawBatchRatio, NotEnoughSharesWithdrawn(vars.batchSharesPercent));

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

    /// @inheritdoc IVault
    function skipWithdrawBatch() external whenNotPaused onlyRole(OPERATOR_ROLE) notInReshufflingMode {
        require(status == VaultStatus.DepositBatchProcessingFinished, IncorrectVaultStatus(status));
        uint256 bufferedSharesToWithdrawCached = bufferedSharesToWithdraw;
        uint256 batchSharesPercent = _calculateSharesPercent(bufferedSharesToWithdrawCached);
        require(batchSharesPercent < minWithdrawBatchRatio, CannotSkipBatch());

        if (bufferedSharesToWithdrawCached >= forcedWithdrawThreshold) {
            uint256 batchProcessingDelay = block.number - lastResolvedWithdrawBatchBlock;
            require(batchProcessingDelay < forcedBatchBlockLimit, CannotSkipForcedBatch());
        }

        status = VaultStatus.Idle;
        emit WithdrawBatchSkipped(withdrawBatchId, bufferedSharesToWithdrawCached);
    }

    /// @inheritdoc IVault
    function reportWithdraw(uint256 notionAmount) external whenNotPaused onlyContainer {
        require(status == VaultStatus.WithdrawBatchProcessingStarted, IncorrectVaultStatus(status));
        require(notionAmount > 0, IncorrectReport());

        (, uint256 containerIndex) = _containers.indexOf(msg.sender);

        uint256 mask = 1 << containerIndex;
        uint256 reportBitmask = _withdrawReportBitmask;
        require(reportBitmask & mask == 0, ContainerAlreadyReported(msg.sender));

        _withdrawReportBitmask = reportBitmask | mask;
        uint256 previousBatchId = withdrawBatchId - 1;
        withdrawBatchTotalNotion[previousBatchId] += notionAmount;
        totalUnclaimedNotionForWithdraw += notionAmount;

        notion.safeTransferFrom(msg.sender, address(this), notionAmount);

        emit WithdrawReportReceived(msg.sender, previousBatchId, notionAmount);
    }

    /// @inheritdoc IVault
    function resolveWithdrawBatch() external whenNotPaused onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.WithdrawBatchProcessingStarted, IncorrectVaultStatus(status));
        require(isWithdrawReportComplete(), MissingContainerReport());

        status = VaultStatus.Idle;
        uint256 previousBatchId = withdrawBatchId - 1;
        lastResolvedWithdrawBatchId = previousBatchId;
        _withdrawReportBitmask = 0;

        emit WithdrawBatchProcessingFinished(previousBatchId, withdrawBatchTotalNotion[previousBatchId]);
    }

    function _calculateSharesPercent(uint256 shares) internal view returns (uint256) {
        uint256 totalSupplyCached = totalSupply();
        require(totalSupplyCached > 0, Errors.ZeroAmount());
        return shares.mulDiv(MAX_BPS, totalSupplyCached);
    }

    /// @inheritdoc IVault
    function pause() external whenNotPaused onlyRole(EMERGENCY_PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IVault
    function unpause() external onlyRole(EMERGENCY_PAUSER_ROLE) {
        _unpause();
    }
}
