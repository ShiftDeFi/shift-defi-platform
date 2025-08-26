// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
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

contract Vault is
    IVault,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableAddressSetExtended for EnumerableSet.AddressSet;
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 private constant CONTAINER_MANAGER_ROLE = keccak256("CONTAINER_MANAGER_ROLE");
    bytes32 private constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 private constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    uint256 private constant BURN_POSITION_ID = 0;
    uint256 private constant VAULT_POSITION_ID = 1;
    uint256 private constant MAX_CONTAINERS = 256;
    uint256 private constant MAX_BPS = 10_000;

    uint256 public maxDepositAmount;
    uint256 public minDepositAmount;
    uint256 public maxDepositBatchSize;
    uint256 public minDepositBatchSize;
    uint256 public minWithdrawBatchRatio;

    VaultStatus public status;

    IERC20 public notion;
    uint256 private _nextPositionId;
    uint256 public unallocatedNotionAmount;

    // Position Id => shares amount
    mapping(uint256 => uint256) private _shares;
    uint256 private _totalShares;

    uint256 public bufferedDeposits;
    uint256 public depositBatchId;
    mapping(uint256 => uint256) private _depositBatchShares;
    mapping(uint256 => uint256) private _depositBatchAmount;

    // Batch Id => Position Id => amount
    mapping(uint256 => mapping(uint256 => uint256)) private _batchPositionDeposit;
    mapping(address => ContainerReport) private _depositReports;
    uint256 private _depositReportBitmask;
    mapping(uint256 => bool) private _isDepositClaimed;

    uint256 public bufferedSharesToWithdraw;
    uint256 public withdrawBatchId;
    mapping(uint256 => uint256) private _withdrawBatchShares;
    mapping(uint256 => uint256) private _withdrawBatchAmount;

    // Batch Id => Position Id => amount
    mapping(uint256 => mapping(uint256 => uint256)) private _batchPositionWithdrawnShares;
    uint256 private _withdrawReportBitmask;
    mapping(uint256 => mapping(uint256 => bool)) private _isWithdrawalClaimed;

    EnumerableSet.AddressSet private _containers;
    mapping(address => uint256) public containerWeights;

    uint256 private _reallocationCounter;
    mapping(address => bool) private _isReallocating;
    mapping(uint256 => uint256) private _acceptedBatchNotion;
    address public collector;

    address public reshufflingGateway;
    bool public isReshuffling;
    bool public isRepairing;

    mapping(uint256 => bool) private _hasClaimedReshufflingGateway;

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
     * @param _name The name of the ERC721 token representing positions
     * @param _symbol The symbol of the ERC721 token representing positions
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
        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();
        __AccessControl_init();
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

        _nextPositionId = VAULT_POSITION_ID;
        _safeMint(address(this), _nextPositionId++);
    }

    function totalShares() external view override returns (uint256) {
        return _totalShares;
    }

    function sharesOf(uint256 positionId) external view override returns (uint256) {
        return _shares[positionId];
    }

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

    // ---- Vault Configuration ----

    function setCollector(address _collector) external onlyRole(CONFIGURATOR_ROLE) {
        require(collector == address(0), CollectorAlreadySet());
        require(_collector != address(0), Errors.ZeroAddress());
        collector = _collector;
        emit CollectorSet(_collector);
    }

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

        require(newWeightSum == previousWeightSum, IncorrectWeights(newWeightSum));
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
        DepositLocalVars memory vars;

        vars.notionCached = notion;
        vars.bufferedDepositsCached = bufferedDeposits;

        vars.positionId = _nextPositionId++;
        _safeMint(onBehalfOf, vars.positionId);
        vars.depositBatchIdCached = depositBatchId;

        vars.notionBalanceBefore = vars.notionCached.balanceOf(address(this));
        vars.notionCached.safeTransferFrom(msg.sender, address(this), amount);
        vars.receivedNotionAmount = vars.notionCached.balanceOf(address(this)) - vars.notionBalanceBefore;

        require(vars.receivedNotionAmount >= amount, Errors.IncorrectAmountReceived());

        require(
            vars.bufferedDepositsCached + vars.receivedNotionAmount <= maxDepositBatchSize,
            DepositBatchCapReached()
        );

        bufferedDeposits = vars.bufferedDepositsCached + vars.receivedNotionAmount;
        _batchPositionDeposit[vars.depositBatchIdCached][vars.positionId] = vars.receivedNotionAmount;

        emit Deposit(msg.sender, onBehalfOf, vars.depositBatchIdCached, vars.positionId, vars.receivedNotionAmount);
    }

    function claimDeposit(uint256 positionId, uint256 batchId) external nonReentrant {
        _requireOwned(positionId);
        require(!_isDepositClaimed[positionId], AlreadyClaimed());

        uint256 depositAmount = _batchPositionDeposit[batchId][positionId];
        require(depositAmount > 0, NothingToClaim());

        uint256 batchShares = _depositBatchShares[batchId];
        if (batchShares == 0) {
            if (batchId < depositBatchId) {
                revert BatchYieldedNoShares();
            } else {
                revert IncorrectBatchId();
            }
        }

        uint256 totalBatchDeposit = _depositBatchAmount[batchId];
        require(totalBatchDeposit > 0, IncorrectBatchId());

        uint256 sharesAmount = depositAmount.mulDiv(batchShares, totalBatchDeposit);

        _isDepositClaimed[positionId] = true;

        _updateShares(VAULT_POSITION_ID, positionId, sharesAmount);

        emit DepositClaimed(positionId, batchId, sharesAmount);
    }

    function withdraw(uint256 positionId, uint256 sharesPercent) external nonReentrant {
        require(sharesPercent > 0 && sharesPercent <= MAX_BPS, Errors.IncorrectAmount());
        require(_requireOwned(positionId) == msg.sender, Errors.Unauthorized());

        WithdrawLocalVars memory vars;
        vars.withdrawBatchIdCached = withdrawBatchId;

        require(_batchPositionWithdrawnShares[vars.withdrawBatchIdCached][positionId] == 0, OneWithdrawPerBatch());

        vars.sharesToBurn = _shares[positionId].mulDiv(sharesPercent, MAX_BPS);

        bufferedSharesToWithdraw += vars.sharesToBurn;

        _batchPositionWithdrawnShares[vars.withdrawBatchIdCached][positionId] = vars.sharesToBurn;

        _updateShares(positionId, VAULT_POSITION_ID, vars.sharesToBurn);

        emit Withdraw(msg.sender, vars.withdrawBatchIdCached, positionId, vars.sharesToBurn);
    }

    function claimWithdraw(uint256 positionId, uint256 batchId) external nonReentrant {
        address owner = _requireOwned(positionId);
        require(!_isWithdrawalClaimed[batchId][positionId], AlreadyClaimed());

        uint256 withdrawnShares = _batchPositionWithdrawnShares[batchId][positionId];
        require(withdrawnShares > 0, NothingToClaim());

        uint256 batchAmount = _withdrawBatchAmount[batchId];
        require(batchAmount > 0, IncorrectBatchId());

        uint256 totalBatchShares = _withdrawBatchShares[batchId];
        require(totalBatchShares > 0, IncorrectBatchId());

        uint256 amountToClaim = withdrawnShares.mulDiv(batchAmount, totalBatchShares);

        _isWithdrawalClaimed[batchId][positionId] = true;

        _updateShares(VAULT_POSITION_ID, BURN_POSITION_ID, withdrawnShares);

        if (_shares[positionId] == 0) {
            _burn(positionId);
        }

        notion.safeTransfer(owner, amountToClaim);

        emit WithdrawClaimed(msg.sender, positionId, batchId, amountToClaim);
    }

    function claimReshufflingGateway(uint256 positionId) external nonReentrant {
        require(isRepairing, NotInRepairingMode());
        require(!_hasClaimedReshufflingGateway[positionId], AlreadyClaimed());

        _hasClaimedReshufflingGateway[positionId] = true;

        IReshufflingGateway(reshufflingGateway).withdraw(positionId);
        emit ReshufflingGatewayClaimed(positionId);
    }

    // ---- Deposit Batch Processing ----

    function startDepositBatchProcessing() external onlyRole(OPERATOR_ROLE) notInRepairingMode notInReshufflingMode {
        require(status == VaultStatus.Idle, IncorrectStatus());

        DepositBatchProcessingLocalVars memory vars;
        vars.batchAmount = bufferedDeposits;

        // NOTE: Skip deposit batch processing if not enough notion was deposited
        if (vars.batchAmount < minDepositBatchSize) {
            status = VaultStatus.DepositBatchProcessingFinished;
            emit DepositBatchSkipped(depositBatchId, vars.batchAmount);
            return;
        }

        bufferedDeposits = 0;

        vars.batchId = depositBatchId++;
        _depositBatchAmount[vars.batchId] = vars.batchAmount;

        uint256 length = _containers.length();
        require(length > 0, NoContainers());

        for (uint256 i = 0; i < length; ++i) {
            address container = _containers.at(i);
            uint256 containerWeight = containerWeights[container];

            if (i < length - 1) {
                vars.containerAmount = vars.batchAmount.mulDiv(containerWeight, MAX_BPS);
            } else {
                // NOTE: Last container takes all division dust
                vars.containerAmount = vars.batchAmount - vars.distributedAmount;
            }

            vars.distributedAmount += vars.containerAmount;
            IContainerPrincipal(container).registerDepositRequest(vars.containerAmount);
        }

        status = VaultStatus.DepositBatchProcessingStarted;
        emit DepositBatchProcessingStarted(vars.batchId, vars.batchAmount);
    }

    function reportDeposit(ContainerReport calldata report, uint256 notionRemainder) external onlyContainer {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectStatus());
        require(report.nav1 >= report.nav0, IncorrectReport());

        (, uint256 containerIndex) = _containers.indexOf(msg.sender);
        uint256 mask = 1 << containerIndex;
        uint256 reportBitmask = _depositReportBitmask;

        if (reportBitmask & mask == 0) {
            _depositReports[msg.sender] = report;
            _depositReportBitmask = reportBitmask | mask;
        } else {
            // NOTE: Consecutive report happens due to reallocation and we do not need to update nav0 for that container
            require(_isReallocating[msg.sender], ContainerNotReallocating());
            ContainerReport storage previousReport = _depositReports[msg.sender];
            previousReport.nav1 = report.nav1;

            _isReallocating[msg.sender] = false;
            _reallocationCounter -= 1;
        }

        if (notionRemainder > 0) {
            unallocatedNotionAmount += notionRemainder;
            notion.safeTransferFrom(msg.sender, address(this), notionRemainder);
        }

        emit DepositReportReceived(msg.sender, depositBatchId - 1, report.nav0, report.nav1);
    }

    function resolveDepositBatch() external onlyRole(OPERATOR_ROLE) returns (uint256) {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectBatchStatus());
        require(unallocatedNotionAmount == 0, NotionNotAllocated());
        require(_reallocationCounter == 0, ReallocationUnfinished());

        ResolveDepositBatchLocalVars memory vars;
        vars.length = _containers.length();

        // Make sure each container has reported at least once
        vars.depositReportBitmaskCached = _depositReportBitmask;
        if (vars.depositReportBitmaskCached != (1 << vars.length) - 1) {
            for (uint256 i = 0; i < vars.length; ++i) {
                if ((vars.depositReportBitmaskCached & (1 << i)) == 0) {
                    revert MissingContainerReport(_containers.at(i));
                }
            }
        }

        for (uint256 i = 0; i < vars.length; ++i) {
            address container = _containers.at(i);

            if (containerWeights[container] == 0) {
                continue;
            }

            ContainerReport memory report = _depositReports[container];

            vars.totalNav0 += report.nav0;
            vars.totalNav1 += report.nav1;
        }

        // NOTE: totalNav1 > totalNav0 is enforced in reportDeposit()
        vars.batchDeltaNav = vars.totalNav1 - vars.totalNav0;

        vars.batchShares = vars.batchDeltaNav.mulDiv(_totalShares + 1, vars.totalNav0 + 1);

        vars.previousBatchId = depositBatchId - 1;
        _depositBatchShares[vars.previousBatchId] = vars.batchShares;
        _mintShares(VAULT_POSITION_ID, vars.batchShares);

        // Flush report states
        _depositReportBitmask = 0;

        status = VaultStatus.DepositBatchProcessingFinished;
        emit DepositBatchProcessingFinished(vars.previousBatchId, vars.batchShares, vars.batchDeltaNav, vars.totalNav1);
        return vars.batchShares;
    }

    function acceptUnallocatedNotion() external onlyRole(OPERATOR_ROLE) returns (uint256) {
        require(status == VaultStatus.DepositBatchProcessingStarted, IncorrectBatchStatus());
        require(_reallocationCounter == 0, ReallocationUnfinished());

        AcceptUnallocatedNotionLocalVars memory vars;

        vars.unallocatedNotionAmountCached = unallocatedNotionAmount;
        require(vars.unallocatedNotionAmountCached > 0, NothingToReallocate());
        unallocatedNotionAmount = 0;

        vars.depositReportBitmaskCached = _depositReportBitmask;

        vars.length = _containers.length();
        for (uint256 i = 0; i < vars.length; ++i) {
            address container = _containers.at(i);
            if (containerWeights[container] == 0) {
                continue;
            }
            require(vars.depositReportBitmaskCached & (1 << i) != 0, MissingContainerReport(container));
        }

        vars.previousBatchId = depositBatchId - 1;
        _acceptedBatchNotion[vars.previousBatchId] = vars.unallocatedNotionAmountCached;

        notion.safeTransfer(collector, vars.unallocatedNotionAmountCached);

        emit UnallocatedNotionAccepted(vars.previousBatchId, vars.unallocatedNotionAmountCached);
        return vars.unallocatedNotionAmountCached;
    }

    function reallocateNotion(address container, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        uint256 unallocatedNotionAmountCached = unallocatedNotionAmount;
        require(amount > 0 && amount <= unallocatedNotionAmountCached, Errors.IncorrectAmount());
        require(_isContainer(container), NotContainer());

        unallocatedNotionAmount = unallocatedNotionAmountCached - amount;

        _isReallocating[container] = true;
        _reallocationCounter += 1;

        IContainerPrincipal(container).registerDepositRequest(amount);
    }

    // ---- Withdraw Batch Processing ----

    function startWithdrawBatchProcessing() external onlyRole(OPERATOR_ROLE) notInReshufflingMode {
        require(status == VaultStatus.DepositBatchProcessingFinished, IncorrectBatchStatus());

        WithdrawBatchProcessingLocalVars memory vars;
        vars.bufferedSharesToWithdrawCached = bufferedSharesToWithdraw;
        bufferedSharesToWithdraw = 0;

        // NOTE: Skip withdraw batch processing if not enough notion was withdrawn
        if (_calculateTotalSharesRatio(vars.bufferedSharesToWithdrawCached) < minWithdrawBatchRatio) {
            status = VaultStatus.Idle;
            emit WithdrawBatchSkipped(withdrawBatchId, vars.bufferedSharesToWithdrawCached);
            return;
        }

        vars.batchSharesPercent = _calculateTotalSharesRatio(vars.bufferedSharesToWithdrawCached);

        vars.previousBatchId = withdrawBatchId++;
        _withdrawBatchShares[vars.previousBatchId] = vars.bufferedSharesToWithdrawCached;

        uint256 length = _containers.length();

        for (uint256 i = 0; i < length; ++i) {
            IContainerPrincipal(_containers.at(i)).registerWithdrawRequest(vars.batchSharesPercent);
        }

        status = VaultStatus.WithdrawBatchProcessingStarted;
        emit WithdrawBatchProcessingStarted(
            vars.previousBatchId,
            vars.bufferedSharesToWithdrawCached,
            vars.batchSharesPercent
        );
    }

    function reportWithdraw(uint256 notionAmount) external onlyContainer {
        require(status == VaultStatus.WithdrawBatchProcessingStarted, IncorrectBatchStatus());

        (, uint256 containerIndex) = _containers.indexOf(msg.sender);
        uint256 mask = 1 << containerIndex;
        uint256 reportBitmask = _withdrawReportBitmask;

        require(reportBitmask & mask == 0, AlreadyReported());
        _withdrawReportBitmask = reportBitmask | mask;

        uint256 previousBatchId = withdrawBatchId - 1;
        _withdrawBatchAmount[previousBatchId] += notionAmount;
        notion.safeTransferFrom(msg.sender, address(this), notionAmount);

        emit WithdrawReportReceived(msg.sender, previousBatchId, notionAmount);
    }

    function resolveWithdrawBatch() external onlyRole(OPERATOR_ROLE) {
        require(status == VaultStatus.WithdrawBatchProcessingStarted, IncorrectBatchStatus());

        ResolveWithdrawBatchLocalVars memory vars;
        vars.previousBatchId = withdrawBatchId - 1;
        vars.expectedAmount = _withdrawBatchAmount[vars.previousBatchId];
        vars.actualAmount = notion.balanceOf(address(this)) - bufferedDeposits;

        require(
            vars.actualAmount >= vars.expectedAmount,
            NotEnoughFundsWithdrawn(vars.expectedAmount, vars.actualAmount)
        );

        vars.withdrawReportBitmaskCached = _withdrawReportBitmask;
        _withdrawReportBitmask = 0;

        vars.length = _containers.length();

        // Make sure each container has reported at least once
        if (vars.withdrawReportBitmaskCached != (1 << vars.length) - 1) {
            for (uint256 i = 0; i < vars.length; ++i) {
                if ((vars.withdrawReportBitmaskCached & (1 << i)) == 0) {
                    revert MissingContainerReport(_containers.at(i));
                }
            }
        }

        status = VaultStatus.Idle;
        emit WithdrawBatchProcessingFinished(vars.previousBatchId, vars.expectedAmount, vars.actualAmount);
    }

    function getAcceptedNotionToClaim(uint256 positionId, uint256 batchId) external view returns (uint256) {
        uint256 depositAmount = _batchPositionDeposit[batchId][positionId];
        require(depositAmount > 0, NothingToClaim());

        uint256 totalBatchDeposit = _depositBatchAmount[batchId];
        require(totalBatchDeposit > 0, IncorrectBatchId());

        return depositAmount.mulDiv(_acceptedBatchNotion[batchId], totalBatchDeposit);
    }

    function _mintShares(uint256 positionId, uint256 value) internal {
        if (positionId == 0) {
            revert InvalidSharesReceiver(0);
        }
        _updateShares(0, positionId, value);
    }

    function _burnShares(uint256 positionId, uint256 value) internal {
        if (positionId == 0) {
            revert InvalidSharesSender(0);
        }
        _updateShares(positionId, 1, value);
    }

    function _updateShares(uint256 fromPosition, uint256 toPosition, uint256 value) internal {
        if (fromPosition != BURN_POSITION_ID) {
            _requireOwned(fromPosition);
        }
        if (toPosition != BURN_POSITION_ID) {
            _requireOwned(toPosition);
        }

        if (fromPosition == BURN_POSITION_ID) {
            _totalShares += value;
        } else {
            uint256 fromShares = _shares[fromPosition];
            if (fromShares < value) {
                revert InsufficientShares(fromPosition, fromShares, value);
            }
            unchecked {
                // Overflow not possible: value <= fromShares <= totalShares.
                _shares[fromPosition] = fromShares - value;
            }
        }

        if (toPosition == BURN_POSITION_ID) {
            unchecked {
                // Overflow not possible: value <= totalShares or value <= fromShares <= totalShares.
                _totalShares -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _shares[toPosition] += value;
            }
        }
        // emit TransferShares
    }

    function _calculateTotalSharesRatio(uint256 amountShares) internal view returns (uint256) {
        if (_totalShares == 0) {
            return 0;
        }
        return amountShares.mulDiv(MAX_BPS, _totalShares);
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
