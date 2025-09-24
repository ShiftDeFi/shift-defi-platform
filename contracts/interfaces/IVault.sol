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

    struct ClaimDepositLocalVars {
        uint256 depositAmount;
        uint256 batchTotalNotion;
        uint256 batchNotionRemainder;
        uint256 batchTotalShares;
        uint256 sharesToClaim;
        uint256 notionToClaim;
    }

    struct WithdrawLocalVars {
        uint256 sharesToBurn;
        uint256 positionShares;
        uint256 withdrawBatchIdCached;
    }

    struct ClaimWithdrawLocalVars {
        uint256 withdrawnShares;
        uint256 batchTotalNotion;
        uint256 batchTotalShares;
        uint256 notionToClaim;
    }

    struct DepositBatchProcessingLocalVars {
        uint256 batchId;
        uint256 totalBatchDepositAmount;
        uint256 containersNumber;
        uint256 lastContainerIndex;
        uint256 containerAmount;
        uint256 distributedNotion;
    }

    struct ResolveDepositBatchLocalVars {
        uint256 previousBatchId;
        uint256 containersNumber;
        uint256 totalNav0;
        uint256 totalNav1;
        uint256 batchDeltaNav;
        uint256 batchShares;
    }

    struct WithdrawBatchProcessingLocalVars {
        uint256 bufferedSharesToWithdrawCached;
        uint256 batchSharesPercent;
        uint256 batchId;
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

    event Deposit(address indexed user, address indexed onBehalfOf, uint256 indexed batchId, uint256 amount);
    event DepositClaimed(
        address indexed user,
        address indexed onBehalfOf,
        uint256 indexed batchId,
        uint256 sharesClaimed,
        uint256 notionClaimed
    );

    event Withdraw(address indexed user, uint256 indexed batchId, uint256 amountShares);
    event WithdrawClaimed(address indexed user, address indexed onBehalfOf, uint256 indexed batchId, uint256 amount);

    event DepositBatchProcessingStarted(uint256 batchId, uint256 batchAmount);
    event DepositBatchSkipped(uint256 batchId, uint256 batchAmount);
    event DepositReportReceived(
        address indexed container,
        uint256 indexed batchId,
        uint256 nav0,
        uint256 nav1,
        uint256 notionRemainder
    );
    event DepositBatchProcessingFinished(
        uint256 batchId,
        uint256 batchShares,
        uint256 batchDeltaNav,
        uint256 totalNav1
    );

    event WithdrawBatchProcessingStarted(uint256 batchId, uint256 batchShares, uint256 batchSharesPercent);
    event WithdrawBatchSkipped(uint256 batchId, uint256 batchAmount);
    event WithdrawReportReceived(address indexed container, uint256 indexed batchId, uint256 notionAmount);
    event WithdrawBatchProcessingFinished(uint256 batchId, uint256 withdrawnNotionAmount);

    event ReshufflingGatewayUpdated(address indexed previousGateway, address indexed newGateway);
    event ReshufflingModeUpdated(bool reshufflingMode);
    event RepairingModeSet();
    event ReshufflingGatewayClaimed(address account);

    // ---- Errors ----

    // Access Control
    error NotContainer();

    // State
    error AlreadyClaimed();
    error ContainerAlreadyExists();
    error ContainerNotFound(address container);
    error ContainerAlreadyReported();
    error ContainerNotReallocating();
    error NoContainers();
    error NotInRepairingMode();
    error NotEnoughNotion();
    error NotEnoughSharesWithdrawn();
    error ReshufflingGatewayNotSet();
    error VaultIsInRepairingMode();
    error VaultIsInReshufflingMode();

    // Input Validation
    error NothingToWithdraw();
    error IncorrectBatchId();
    error IncorrectBatchStatus();
    error IncorrectReport();
    error IncorrectStatus();
    error IncorrectWeights(uint256 weightsSum);

    // Business Logic
    error DepositBatchCapReached();
    error DepositBatchSizeTooSmall();
    error CannotSkipBatch();
    error IncorrectNotionDistribution();
    error MaxContainersReached();
    error MissingContainerReport();
    error NotionNotAllocated();
    error NothingToClaim();

    // ---- Functions ----

    function notion() external view returns (IERC20);

    function reportDeposit(ContainerReport memory report, uint256 notionRemainder) external;

    function reportWithdraw(uint256 notionRemainder) external;

    function isContainer(address container) external view returns (bool);

    function isRepairing() external view returns (bool);

    function isReshuffling() external view returns (bool);

    function getContainers() external view returns (address[] memory, uint256[] memory);
}
