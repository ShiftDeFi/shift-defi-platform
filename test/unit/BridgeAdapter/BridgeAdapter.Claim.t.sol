// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {BridgeAdapterBase} from "test/unit/BridgeAdapter/BridgeAdapterBase.t.sol";

contract BridgeAdapterClaimTest is BridgeAdapterBase {
    function setUp() public override {
        super.setUp();
    }

    function test_Claim() public {
        notion.mint(address(bridgeAdapter), BRIDGE_AMOUNT);
        bridgeAdapter.finalizeBridge(users.alice, address(notion), BRIDGE_AMOUNT);

        uint256 balanceBefore = IERC20(address(notion)).balanceOf(users.alice);
        uint256 adapterBalanceBefore = IERC20(address(notion)).balanceOf(address(bridgeAdapter));
        uint256 claimableAmountBefore = bridgeAdapter.claimableAmounts(users.alice, address(notion));
        vm.startPrank(users.alice);
        IERC20(address(notion)).approve(address(bridgeAdapter), BRIDGE_AMOUNT);
        uint256 claimedAmount = bridgeAdapter.claim(address(notion));
        vm.stopPrank();
        uint256 balanceAfter = IERC20(address(notion)).balanceOf(users.alice);
        uint256 adapterBalanceAfter = IERC20(address(notion)).balanceOf(address(bridgeAdapter));

        assertEq(claimedAmount, BRIDGE_AMOUNT, "test_Claim: Incorrect claimed amount");
        assertEq(balanceAfter - balanceBefore, BRIDGE_AMOUNT, "test_Claim: Incorrect claimer balance before and after");
        assertEq(
            adapterBalanceBefore - adapterBalanceAfter,
            BRIDGE_AMOUNT,
            "test_Claim: Incorrect adapter balance before and after"
        );
        assertEq(claimableAmountBefore, BRIDGE_AMOUNT, "test_Claim: Incorrect claimable amount before and after");
        assertEq(
            bridgeAdapter.claimableAmounts(users.alice, address(notion)),
            0,
            "test_Claim: Incorrect claimable amount after"
        );
    }

    function test_RevertIf_Claim_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        bridgeAdapter.claim(address(0));
    }

    function test_RevertIf_Claim_ZeroToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(address(0));
        bridgeAdapter.claim(address(0));
    }

    function test_RevertIf_Claim_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        bridgeAdapter.claim(address(notion));

        bridgeAdapter.finalizeBridge(users.alice, address(notion), BRIDGE_AMOUNT);

        vm.expectRevert(Errors.ZeroAmount.selector);
        bridgeAdapter.claim(address(notion));
    }

    function test_RevertIf_Claim_NotEnoughTokens() public {
        bridgeAdapter.finalizeBridge(users.alice, address(notion), 2 * BRIDGE_AMOUNT);
        notion.mint(address(bridgeAdapter), BRIDGE_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotEnoughTokens.selector, address(notion), 2 * BRIDGE_AMOUNT, BRIDGE_AMOUNT)
        );
        vm.prank(users.alice);
        bridgeAdapter.claim(address(notion));
    }

    function test_FinalizeBridge_UpdatesClaimableAmounts() public {
        uint256 claimableBefore = bridgeAdapter.claimableAmounts(users.alice, address(notion));
        assertEq(claimableBefore, 0, "test_FinalizeBridge: Initial claimable should be zero");

        bridgeAdapter.finalizeBridge(users.alice, address(notion), BRIDGE_AMOUNT);

        uint256 claimableAfter = bridgeAdapter.claimableAmounts(users.alice, address(notion));
        assertEq(claimableAfter, BRIDGE_AMOUNT, "test_FinalizeBridge: Claimable amount not updated correctly");

        bridgeAdapter.finalizeBridge(users.alice, address(notion), BRIDGE_AMOUNT);

        uint256 claimableAccumulated = bridgeAdapter.claimableAmounts(users.alice, address(notion));
        assertEq(
            claimableAccumulated,
            2 * BRIDGE_AMOUNT,
            "test_FinalizeBridge: Claimable amount not accumulated correctly"
        );
    }

    function test_RevertIf_FinalizeBridge_ZeroAmount() public {
        vm.expectRevert(Errors.IncorrectAmount.selector);
        bridgeAdapter.finalizeBridge(users.alice, address(notion), 0);
    }

    function test_RevertIf_FinalizeBridge_ZeroClaimer() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        bridgeAdapter.finalizeBridge(address(0), address(notion), BRIDGE_AMOUNT);
    }

    function test_RevertIf_FinalizeBridge_ZeroToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        bridgeAdapter.finalizeBridge(users.alice, address(0), BRIDGE_AMOUNT);
    }
}
