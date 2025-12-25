// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
        uint256 notionToClaim;
    }

    struct DepositBatchProcessingLocalVars {
        uint256 totalBatchDepositAmount;
        uint256 containersNumber;
        uint256 batchId;
        uint256 undistributedWeight;
        uint256 undistributedNotionAmount;
        uint256 containerAmount;
    }

    struct ResolveDepositBatchLocalVars {
        uint256 previousBatchId;
        uint256 containersNumber;
        uint256 totalNav0;
        uint256 totalNav1;
        uint256 batchDeltaNav;
        uint256 totalSupplyCached;
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
    error ContainerWeightZero(address container);
    error IncorrectContainerAmount(address container);

    // ---- Functions ----

    /**
     * @notice Sets the reshuffling gateway address.
     * @dev Can only be called by accounts with EMERGENCY_MANAGER_ROLE.
     * @param _reshufflingGateway The address of the reshuffling gateway contract
     */
    function setReshufflingGateway(address _reshufflingGateway) external;

    /**
     * @notice Sets the reshuffling mode state.
     * @dev Can only be called by accounts with EMERGENCY_MANAGER_ROLE. Requires reshuffling gateway to be set.
     * @param _isReshuffling The new reshuffling mode state
     */
    function setReshufflingMode(bool _isReshuffling) external;

    /**
     * @notice Activates the repairing mode.
     * @dev Can only be called by accounts with EMERGENCY_MANAGER_ROLE. Requires reshuffling gateway to be set and vault not already in repairing mode.
     */
    function activateRepairingMode() external;

    /**
     * @notice Sets the maximum deposit amount per transaction.
     * @dev Can only be called by accounts with CONFIGURATOR_ROLE.
     * @param _maxDepositAmount The maximum amount that can be deposited in a single transaction
     */
    function setMaxDepositAmount(uint256 _maxDepositAmount) external;

    /**
     * @notice Sets the minimum deposit amount.
     * @dev Can only be called by accounts with CONFIGURATOR_ROLE.
     * @param _minDepositAmount The minimum amount required for a deposit transaction
     */
    function setMinDepositAmount(uint256 _minDepositAmount) external;

    /**
     * @notice Sets the maximum deposit batch size.
     * @dev Can only be called by accounts with CONFIGURATOR_ROLE.
     * @param _maxDepositBatchSize The maximum total amount that can be accumulated in a deposit batch
     */
    function setMaxDepositBatchSize(uint256 _maxDepositBatchSize) external;

    /**
     * @notice Sets the minimum deposit batch size.
     * @dev Can only be called by accounts with CONFIGURATOR_ROLE.
     * @param _minDepositBatchSize The minimum total amount required to start processing a deposit batch
     */
    function setMinDepositBatchSize(uint256 _minDepositBatchSize) external;

    /**
     * @notice Sets the minimum withdraw batch ratio.
     * @dev Can only be called by accounts with CONFIGURATOR_ROLE. Ratio is in basis points (10000 = 100%).
     * @param _minWithdrawBatchRatio The minimum percentage of total shares that must be withdrawn to start processing a withdraw batch
     */
    function setMinWithdrawBatchRatio(uint256 _minWithdrawBatchRatio) external;

    /**
     * @notice Returns all registered containers and their weights.
     * @return containers Array of container addresses
     * @return weights Array of corresponding weights in basis points
     */
    function getContainers() external view returns (address[] memory containers, uint256[] memory weights);

    /**
     * @notice Adds a new container to the vault.
     * @dev Can only be called by accounts with CONTAINER_MANAGER_ROLE. If this is the first container, it automatically gets 100% weight.
     * @param container The address of the container contract to add
     */
    function addContainer(address container) external;

    /**
     * @notice Sets the weights for multiple containers.
     * @dev Can only be called by accounts with CONTAINER_MANAGER_ROLE. Requires vault status to be Idle. Setting weight to 0 removes the container.
     * @param containers Array of container addresses to update weights for
     * @param weights Array of corresponding weights in basis points (10000 = 100%)
     */
    function setContainerWeights(address[] calldata containers, uint256[] calldata weights) external;

    /**
     * @notice Checks if an address is a registered container.
     * @param container The address to check
     * @return True if the address is a registered container, false otherwise
     */
    function isContainer(address container) external view returns (bool);

    /**
     * @notice Deposits notion tokens into the vault.
     * @dev Deposits are buffered and processed in batches. The amount must be between minDepositAmount and maxDepositAmount.
     * @param amount The amount of notion tokens to deposit
     * @param onBehalfOf The address that will receive the vault shares
     */
    function deposit(uint256 amount, address onBehalfOf) external;

    /**
     * @notice Deposits notion tokens into the vault using ERC20 permit.
     * @dev Allows depositing without a prior approval transaction by using ERC20 permit signature.
     * @param amount The amount of notion tokens to deposit
     * @param onBehalfOf The address that will receive the vault shares
     * @param deadline The deadline for the permit signature
     * @param v The recovery id of the permit signature
     * @param r The r component of the permit signature
     * @param s The s component of the permit signature
     */
    function depositWithPermit(
        uint256 amount,
        address onBehalfOf,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Claims vault shares and notion remainder for a completed deposit batch.
     * @dev Can only be called after the deposit batch has been resolved. Calculates shares based on the batch's NAV change.
     * @param batchId The ID of the deposit batch to claim from
     * @param onBehalfOf The address that will receive the shares and notion remainder
     */
    function claimDeposit(uint256 batchId, address onBehalfOf) external;

    /**
     * @notice Initiates a withdrawal by burning a percentage of the caller's vault shares.
     * @dev The shares are transferred to the vault and buffered for batch processing. The percentage is in basis points (10000 = 100%).
     * @param sharesPercent The percentage of caller's shares to withdraw, in basis points
     */
    function withdraw(uint256 sharesPercent) external;

    /**
     * @notice Claims notion tokens for a completed withdrawal batch.
     * @dev Can only be called after the withdrawal batch has been resolved. Burns the shares and transfers notion tokens.
     * @param batchId The ID of the withdrawal batch to claim from
     * @param onBehalfOf The address that will receive the notion tokens
     */
    function claimWithdraw(uint256 batchId, address onBehalfOf) external;

    /**
     * @notice Claims assets from the reshuffling gateway for an account.
     * @dev Can only be called when the vault is in repairing mode. Each account can only claim once.
     * @param account The account address to claim assets for
     */
    function claimReshufflingGateway(address account) external;

    /**
     * @notice Checks if all containers have submitted their deposit reports.
     * @return True if all containers have reported, false otherwise
     */
    function isDepositReportComplete() external view returns (bool);

    /**
     * @notice Starts processing a new deposit batch.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires vault status to be Idle and buffered deposits to meet minimum batch size. Distributes deposits to containers based on their weights.
     */
    function startDepositBatchProcessing() external;

    /**
     * @notice Skips processing the current deposit batch if it's too small.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires vault status to be Idle and buffered deposits to be below minimum batch size.
     */
    function skipDepositBatch() external;

    /**
     * @notice Reports deposit results from a container.
     * @dev Can only be called by registered containers. Each container can only report once per batch. Requires nav1 >= nav0.
     * @param report The container report containing NAV values before and after the deposit
     * @param notionRemainder Any notion tokens that couldn't be deposited and should be returned to users
     */
    function reportDeposit(ContainerReport calldata report, uint256 notionRemainder) external;

    /**
     * @notice Resolves a deposit batch after all containers have reported.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Calculates total NAV change and mints corresponding vault shares.
     */
    function resolveDepositBatch() external;

    /**
     * @notice Checks if all containers have submitted their withdrawal reports.
     * @return True if all containers have reported, false otherwise
     */
    function isWithdrawReportComplete() external view returns (bool);

    /**
     * @notice Starts processing a new withdrawal batch.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires vault status to be DepositBatchProcessingFinished and buffered shares to meet minimum batch ratio.
     */
    function startWithdrawBatchProcessing() external;

    /**
     * @notice Skips processing the current withdrawal batch if it's too small.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Requires vault status to be DepositBatchProcessingFinished and buffered shares to be below minimum batch ratio.
     */
    function skipWithdrawBatch() external;

    /**
     * @notice Reports withdrawal results from a container.
     * @dev Can only be called by registered containers. Each container can only report once per batch. Transfers notion tokens from the container to the vault.
     * @param notionAmount The amount of notion tokens the container is returning for the withdrawal
     */
    function reportWithdraw(uint256 notionAmount) external;

    /**
     * @notice Resolves a withdrawal batch after all containers have reported.
     * @dev Can only be called by accounts with OPERATOR_ROLE. Sets vault status back to Idle, making it ready for the next deposit batch.
     */
    function resolveWithdrawBatch() external;

    /**
     * @notice Returns the notion token contract address.
     * @return The IERC20 token contract representing the notion token
     */
    function notion() external view returns (IERC20);

    /**
     * @notice Returns whether the vault is in repairing mode.
     * @return True if the vault is in repairing mode, false otherwise
     */
    function isRepairing() external view returns (bool);

    /**
     * @notice Returns whether the vault is in reshuffling mode.
     * @return True if the vault is in reshuffling mode, false otherwise
     */
    function isReshuffling() external view returns (bool);
}
