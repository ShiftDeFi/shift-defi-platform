// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ContainerLocalBaseTest} from "test/unit/ContainerLocal/ContainerLocalBase.t.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {Errors} from "contracts/libraries/Errors.sol";

contract ContainerLocalReshufflingTest is ContainerLocalBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_RevertIf_NotInReshufflingModeAndWithdrawToReshufflingGateway() public {
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ReshufflingModeDisabled.selector);
        containerLocal.withdrawToReshufflingGateway(tokens, amounts);
    }

    function test_RevertIf_ArrayLengthMismatchAndWithdrawToReshufflingGateway() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        containerLocal.withdrawToReshufflingGateway(tokens, amounts);

        tokens = new address[](0);
        amounts = new uint256[](1);

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        containerLocal.withdrawToReshufflingGateway(tokens, amounts);
    }

    function test_RevertIf_WithdrawToReshufflingGateway_ReshufflingGatewayIsZeroAddress() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        bytes32 reshufflingGatewaySlot = bytes32(uint256(13));
        vm.store(address(containerLocal), reshufflingGatewaySlot, bytes32(uint256(0)));

        vm.prank(roles.reshufflingExecutor);
        vm.expectRevert(Errors.ZeroAddress.selector);
        containerLocal.withdrawToReshufflingGateway(tokens, amounts);
    }

    function test_WithdrawToReshufflingGateway() public {
        vm.startPrank(roles.reshufflingManager);
        containerLocal.setReshufflingGateway(address(1));
        containerLocal.enableReshufflingMode();
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = address(notion);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(roles.reshufflingExecutor);
        containerLocal.withdrawToReshufflingGateway(tokens, amounts);
    }
}
