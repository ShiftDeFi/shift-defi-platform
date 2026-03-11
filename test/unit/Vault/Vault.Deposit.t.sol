// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {IVault} from "contracts/interfaces/IVault.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {L1Base} from "test/L1Base.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract VaultDepositTest is L1Base {
    using SafeERC20 for MockERC20;

    function test_Deposit() public {
        _deposit(users.alice, DEPOSIT_AMOUNT);

        assertEq(vault.bufferedDeposits(), DEPOSIT_AMOUNT, "test_Deposit: bufferedDeposits");
        assertEq(notion.balanceOf(address(vault)), DEPOSIT_AMOUNT, "test_Deposit: notionBalanceOfVault");
        assertEq(
            vault.pendingBatchDeposits(vault.depositBatchId(), users.alice),
            DEPOSIT_AMOUNT,
            "test_Deposit: pendingBatchDeposits"
        );
        assertEq(notion.balanceOf(users.alice), 0, "test_Deposit: notionBalanceOfUser");
    }

    function test_Deposit_TwiceInOneBatch() public {
        _deposit(users.alice, DEPOSIT_AMOUNT);
        _deposit(users.alice, 2 * DEPOSIT_AMOUNT);
        uint256 totalDepositAmount = 3 * DEPOSIT_AMOUNT;

        assertEq(vault.bufferedDeposits(), totalDepositAmount, "test_DepositTwiceInOneBatch: bufferedDeposits");
        assertEq(
            notion.balanceOf(address(vault)),
            totalDepositAmount,
            "test_DepositTwiceInOneBatch: notionBalanceOfVault"
        );
        assertEq(
            vault.pendingBatchDeposits(vault.depositBatchId(), users.alice),
            totalDepositAmount,
            "test_DepositTwiceInOneBatch: pendingBatchDeposits"
        );
        assertEq(notion.balanceOf(users.alice), 0, "test_DepositTwiceInOneBatch: notionBalanceOfUser");
    }

    function test_RevertIf_Deposit_OnBehalfOfZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vault.deposit(DEPOSIT_AMOUNT, address(0));
    }

    function test_RevertIf_Deposit_AmountExceedsMaxDepositAmount() public {
        uint256 maxDepositAmount = vault.maxDepositAmount();

        vm.startPrank(users.alice);
        notion.safeIncreaseAllowance(address(vault), maxDepositAmount + 1);

        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.deposit(maxDepositAmount + 1, users.alice);
        vm.stopPrank();
    }

    function test_RevertIf_Deposit_AmountIsLessThanMinDepositAmount() public {
        uint256 minDepositAmount = vault.minDepositAmount();

        vm.startPrank(users.alice);
        notion.safeIncreaseAllowance(address(vault), minDepositAmount - 1);

        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.deposit(minDepositAmount - 1, users.alice);
        vm.stopPrank();
    }

    function test_RevertIf_Deposit_AmountExceedsMaxDepositBatchSize() public {
        uint256 maxDepositBatchSize = vault.maxDepositBatchSize();

        vm.startPrank(users.alice);
        notion.safeIncreaseAllowance(address(vault), maxDepositBatchSize + 1);

        vm.expectRevert(Errors.IncorrectAmount.selector);
        vault.deposit(maxDepositBatchSize + 1, users.alice);
        vm.stopPrank();
    }

    function test_RevertIf_Deposit_BatchCapReached() public {
        uint256 maxDepositAmount = vault.maxDepositAmount();
        _deposit(users.alice, maxDepositAmount);

        vm.prank(roles.configurator);
        vault.setMaxDepositBatchSize(maxDepositAmount);

        vm.expectRevert(IVault.DepositBatchCapReached.selector);
        vault.deposit(maxDepositAmount, users.alice);
        vm.stopPrank();
    }

    function test_DepositWithPermit() public {
        bytes32 structHash = keccak256(
            abi.encode(
                notion.PERMIT_TYPEHASH(),
                users.alice,
                vault,
                DEPOSIT_AMOUNT,
                notion.nonces(users.alice),
                block.timestamp + 1
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", notion.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.alicePrivateKey, digest);

        notion.mint(users.alice, DEPOSIT_AMOUNT);

        vm.prank(users.alice);
        vault.depositWithPermit(DEPOSIT_AMOUNT, users.alice, block.timestamp + 1, v, r, s);

        assertEq(vault.bufferedDeposits(), DEPOSIT_AMOUNT, "test_DepositWithPermit: bufferedDeposits");
        assertEq(notion.balanceOf(address(vault)), DEPOSIT_AMOUNT, "test_DepositWithPermit: notionBalanceOfVault");
        assertEq(
            vault.pendingBatchDeposits(vault.depositBatchId(), users.alice),
            DEPOSIT_AMOUNT,
            "test_DepositWithPermit: pendingBatchDeposits"
        );
        assertEq(notion.balanceOf(users.alice), 0, "test_DepositWithPermit: notionBalanceOfUser");
    }

    function test_RevertIf_DepositWithPermit_OnBehalfOfZeroAddress() public {
        bytes32 structHash = keccak256(
            abi.encode(
                notion.PERMIT_TYPEHASH(),
                users.alice,
                vault,
                DEPOSIT_AMOUNT,
                notion.nonces(users.alice),
                block.timestamp + 1
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", notion.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.alicePrivateKey, digest);

        notion.mint(users.alice, DEPOSIT_AMOUNT);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(users.alice);
        vault.depositWithPermit(DEPOSIT_AMOUNT, address(0), block.timestamp + 1, v, r, s);
    }

    function test_DepositWithPermit_FrontRunnedByNonceIncrement() public {
        uint256 deadline = block.timestamp + 1;

        bytes32 structHash = keccak256(
            abi.encode(
                notion.PERMIT_TYPEHASH(),
                users.alice,
                vault,
                DEPOSIT_AMOUNT,
                notion.nonces(users.alice),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", notion.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.alicePrivateKey, digest);

        notion.mint(users.alice, DEPOSIT_AMOUNT);

        vm.prank(users.bob);
        notion.permit(users.alice, address(vault), DEPOSIT_AMOUNT, deadline, v, r, s);

        vm.prank(users.alice);
        vault.depositWithPermit(DEPOSIT_AMOUNT, users.alice, deadline, v, r, s);

        assertEq(
            vault.bufferedDeposits(),
            DEPOSIT_AMOUNT,
            "test_DepositWithPermit_FrontRunnedByNonceIncrement: bufferedDeposits"
        );
        assertEq(
            notion.balanceOf(address(vault)),
            DEPOSIT_AMOUNT,
            "test_DepositWithPermit_FrontRunnedByNonceIncrement: notionBalanceOfVault"
        );
        assertEq(
            vault.pendingBatchDeposits(vault.depositBatchId(), users.alice),
            DEPOSIT_AMOUNT,
            "test_DepositWithPermit_FrontRunnedByNonceIncrement: pendingBatchDeposits"
        );
        assertEq(
            notion.balanceOf(users.alice),
            0,
            "test_DepositWithPermit_FrontRunnedByNonceIncrement: notionBalanceOfUser"
        );
    }
}
