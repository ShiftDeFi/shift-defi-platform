// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault {
    // -- Enums --

    enum VaultStatus {
        Idle,
        DepositBatchProcessingStarted,
        DepositBatchProcessingFinished,
        WithdrawBatchProcessingStarted
    }

    // -- Structs --

    struct Limits {
        uint256 maxDepositAmount;
        uint256 minDepositAmount;
        uint256 maxDepositBatchSize;
        uint256 minDepositBatchSize;
        uint256 minWithdrawBatchRatio;
    }
    struct RoleAddresses {
        address defaultAdmin;
        address containerManager;
        address operator;
        address configurator;
        address emergencyManager;
    }

    struct ContainerReport {
        uint256 nav0;
        uint256 nav1;
    }

    struct DepositLocalVars {
        IERC20 notionCached;
        uint256 bufferedDepositsCached;
        uint256 positionId;
        uint256 depositBatchIdCached;
        uint256 notionBalanceBefore;
        uint256 receivedNotionAmount;
    }

    struct DepositBatchProcessingLocalVars {
        uint256 batchAmount;
        uint256 batchId;
        uint256 containerAmount;
        uint256 distributedAmount;
    }

    struct ResolveDepositBatchLocalVars {
        uint256 depositReportBitmaskCached;
        uint256 length;
        uint256 totalNav0;
        uint256 totalNav1;
        uint256 batchDeltaNav;
        uint256 batchShares;
        uint256 previousBatchId;
    }

    struct AcceptUnallocatedNotionLocalVars {
        uint256 unallocatedNotionAmountCached;
        uint256 depositReportBitmaskCached;
        uint256 length;
        uint256 previousBatchId;
    }

    struct WithdrawBatchProcessingLocalVars {
        uint256 bufferedSharesToWithdrawCached;
        uint256 batchSharesPercent;
        uint256 previousBatchId;
    }

    struct ResolveWithdrawBatchLocalVars {
        uint256 previousBatchId;
        uint256 expectedAmount;
        uint256 actualAmount;
        uint256 withdrawReportBitmaskCached;
        uint256 length;
    }

    struct WithdrawLocalVars {
        uint256 sharesToBurn;
        uint256 positionShares;
        uint256 withdrawBatchIdCached;
    }

    // -- Events --

    event MaxDepositAmountUpdated(uint256 maxDepositAmount);
    event MinDepositAmountUpdated(uint256 minDepositAmount);
    event MaxDepositBatchSizeUpdated(uint256 maxDepositBatchSize);
    event MinDepositBatchSizeUpdated(uint256 minDepositBatchSize);
    event MinWithdrawBatchRatioUpdated(uint256 minWithdrawBatchRatio);

    event ContainerAdded(address container);
    event ContainerRemoved(address container);
    event ContainerWeightsUpdated(address[] containers, uint256[] weights);

    event CollectorSet(address collector);

    event Deposit(
        address indexed user,
        address indexed onBehalfOf,
        uint256 indexed batchId,
        uint256 positionId,
        uint256 amount
    );
    event DepositClaimed(uint256 positionId, uint256 batchId, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed batchId, uint256 indexed positionId, uint256 amountShares);
    event WithdrawClaimed(address indexed user, uint256 indexed positionId, uint256 indexed batchId, uint256 amount);

    event DepositBatchProcessingStarted(uint256 batchId, uint256 batchAmount);
    event DepositBatchSkipped(uint256 batchId, uint256 batchAmount);
    event DepositReportReceived(address indexed container, uint256 indexed batchId, uint256 nav0, uint256 nav1);
    event DepositBatchProcessingFinished(
        uint256 batchId,
        uint256 batchShares,
        uint256 batchDeltaNav,
        uint256 totalNav1
    );
    event UnallocatedNotionAccepted(uint256 batchId, uint256 amount);

    event WithdrawBatchProcessingStarted(uint256 batchId, uint256 batchShares, uint256 batchSharesPercent);
    event WithdrawBatchSkipped(uint256 batchId, uint256 batchAmount);
    event WithdrawReportReceived(address indexed container, uint256 indexed batchId, uint256 notionAmount);
    event WithdrawBatchProcessingFinished(uint256 batchId, uint256 reportedAmount, uint256 receivedAmount);

    event ReshufflingGatewayUpdated(address indexed previousGateway, address indexed newGateway);
    event ReshufflingModeUpdated(bool reshufflingMode);
    event RepairingModeSet();
    event ReshufflingGatewayClaimed(uint256 positionId);

    // ---- Errors ----

    // Access Control
    error NotContainer();

    // State
    error AlreadyClaimed();
    error AlreadyReported();
    error CollectorAlreadySet();
    error ContainerAlreadyExists();
    error ContainerNotFound(address container);
    error ContainerNotReallocating();
    error NoContainers();
    error NotInRepairingMode();
    error ReshufflingGatewayNotSet();
    error VaultIsInRepairingMode();
    error VaultIsInReshufflingMode();
    error OneWithdrawPerBatch();

    // Input Validation
    error IncorrectBatchId();
    error IncorrectBatchStatus();
    error IncorrectReport();
    error IncorrectStatus();
    error IncorrectWeights(uint256 weightsSum);
    error InvalidSharesReceiver(uint256);
    error InvalidSharesSender(uint256);

    // Business Logic
    error BatchYieldedNoShares();
    error DepositBatchCapReached();
    error InsufficientShares(uint256 positionId, uint256 fromShares, uint256 value);
    error MaxContainersReached();
    error MissingContainerReport(address container);
    error NotEnoughFundsWithdrawn(uint256 expectedAmount, uint256 actualAmount);
    error NotionNotAllocated();
    error NothingToClaim();
    error NothingToReallocate();
    error ReallocationUnfinished();

    // ---- Functions ----

    function notion() external view returns (IERC20);

    function getAcceptedNotionToClaim(uint256 positionId, uint256 batchId) external returns (uint256);

    function reportDeposit(ContainerReport memory report, uint256 notionRemainder) external;

    function reportWithdraw(uint256 notionRemainder) external;

    function sharesOf(uint256 positionId) external view returns (uint256);

    function totalShares() external view returns (uint256);

    function isContainer(address container) external view returns (bool);

    function isRepairing() external view returns (bool);

    function isReshuffling() external view returns (bool);

    function getContainers() external view returns (address[] memory, uint256[] memory);
}
