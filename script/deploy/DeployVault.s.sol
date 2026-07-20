// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Vault} from "contracts/Vault.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

import {RolesRegistry} from "./utils/RolesRegistry.sol";
import {DeploySaltedProxy} from "./utils/DeploySaltedProxy.s.sol";

contract DeployVault is RolesRegistry, DeploySaltedProxy {
    string public vaultName = vm.envString("VAULT_NAME");
    string public vaultSymbol = vm.envString("VAULT_SYMBOL");

    address public notion = vm.envAddress("NOTION_TOKEN_ADDRESS");

    uint256 public maxDepositAmount = vm.envUint("MAX_DEPOSIT_AMOUNT");
    uint256 public minDepositAmount = vm.envUint("MIN_DEPOSIT_AMOUNT");
    uint256 public maxDepositBatchSize = vm.envUint("MAX_DEPOSIT_BATCH_SIZE");
    uint256 public minDepositBatchSize = vm.envUint("MIN_DEPOSIT_BATCH_SIZE");
    uint256 public minWithdrawBatchRatio = vm.envUint("MIN_WITHDRAW_BATCH_RATIO");

    uint256 public forcedDepositThreshold = vm.envUint("FORCED_DEPOSIT_THRESHOLD");
    uint256 public forcedWithdrawThreshold = vm.envUint("FORCED_WITHDRAW_THRESHOLD");
    uint256 public forcedBatchBlockLimit = vm.envUint("FORCED_BATCH_BLOCK_LIMIT");

    uint256 public notionPrecision;

    function run() public {
        _loadRoles();

        notionPrecision = 10 ** IERC20Metadata(notion).decimals();

        IVault.RoleAddresses memory roleAddresses = IVault.RoleAddresses(
            roles.defaultAdmin,
            roles.containerManager,
            roles.operator,
            roles.configurator,
            roles.reshufflingManager,
            roles.reshufflingExecutor,
            roles.emergencyPauser
        );

        IVault.Limits memory limits = IVault.Limits(
            maxDepositAmount * notionPrecision,
            minDepositAmount * notionPrecision,
            maxDepositBatchSize * notionPrecision,
            minDepositBatchSize * notionPrecision,
            minWithdrawBatchRatio
        );

        bytes memory data = abi.encodeWithSelector(
            Vault.initialize.selector,
            vaultName,
            vaultSymbol,
            notion,
            roleAddresses,
            limits,
            forcedDepositThreshold * notionPrecision,
            forcedWithdrawThreshold,
            forcedBatchBlockLimit
        );

        vm.startBroadcast();
        address implementation = address(new Vault());
        _proxifyWithSalt(implementation, data, roles.proxyAdminOwner);
        vm.stopBroadcast();
    }
}
