// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyContainerEnterStrategyTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal notionTokenStrategy;
    MockStrategyInterfaceBased internal nonNotionTokenStrategy;

    function setUp() public override {
        super.setUp();
        (notionTokenStrategy, , ) = _createAndAddStrategyWithTokens(1, 1, true);
        (nonNotionTokenStrategy, , ) = _createAndAddStrategyWithTokens(2, 2, false);
    }

    function test_FirstEnterStrategyWithInputNotionToken() public {
        uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
        MockERC20(address(notion)).mint(address(strategyContainer), inputAmount);
        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = inputAmount;

        notionTokenStrategy.craftNav0(0);
        notionTokenStrategy.craftNav1(inputAmount);

        vm.prank(roles.operator);
        strategyContainer.enterStrategy(address(notionTokenStrategy), inputAmounts, 0);
        assertEq(
            strategyContainer.validateEnterStrategy(address(notionTokenStrategy)),
            true,
            "test_FirstEnterStrategyWithInputNotionToken: Strategy not entered"
        );
    }

    function test_SecondEnterStrategyWithInputNotionToken() public {
        uint256 navAfterHarvest = vm.randomUint(1e18, 1000000e18);
        uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
        MockERC20(address(notion)).mint(address(strategyContainer), navAfterHarvest + inputAmount);
        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = inputAmount;

        notionTokenStrategy.craftNav0(navAfterHarvest);
        notionTokenStrategy.craftNav1(inputAmount + navAfterHarvest);

        vm.prank(roles.operator);
        strategyContainer.enterStrategy(address(notionTokenStrategy), inputAmounts, 0);

        assertEq(
            strategyContainer.validateEnterStrategy(address(notionTokenStrategy)),
            true,
            "test_SecondEnterStrategyWithInputNotionToken: Strategy not entered"
        );
    }

    function test_EnterStrategyWithInputNonNotionToken() public {
        address[] memory inputTokens = nonNotionTokenStrategy.getInputTokens();
        uint256[] memory inputAmounts = new uint256[](inputTokens.length);
        uint256 totalInputAmount = 0;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
            MockERC20(inputTokens[i]).mint(address(strategyContainer), inputAmount);
            inputAmounts[i] = inputAmount;
            totalInputAmount += inputAmount;
        }

        nonNotionTokenStrategy.craftNav0(0);
        nonNotionTokenStrategy.craftNav1(totalInputAmount);

        vm.prank(roles.operator);
        strategyContainer.enterStrategy(address(nonNotionTokenStrategy), inputAmounts, 0);

        assertEq(
            strategyContainer.validateEnterStrategy(address(nonNotionTokenStrategy)),
            true,
            "test_EnterStrategyWithInputNonNotionToken: Strategy not entered"
        );
    }

    function test_EnterStrategyWithRemainder() public {
        address[] memory inputTokens = nonNotionTokenStrategy.getInputTokens();
        uint256[] memory inputAmounts = new uint256[](inputTokens.length);
        uint256 totalInputAmount = 0;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
            MockERC20(inputTokens[i]).mint(address(strategyContainer), inputAmount);
            inputAmounts[i] = inputAmount;
            totalInputAmount += inputAmount;
        }

        uint256[] memory remainingAmounts = new uint256[](inputTokens.length);
        for (uint256 i = 0; i < inputTokens.length; i++) {
            uint256 remainingAmount = vm.randomUint(1e16, inputAmounts[i]);
            MockStrategyInterfaceBased(nonNotionTokenStrategy).approveToken(
                address(inputTokens[i]),
                remainingAmount,
                address(strategyContainer)
            );
            remainingAmounts[i] = remainingAmount;
        }

        nonNotionTokenStrategy.craftNav0(0);
        nonNotionTokenStrategy.craftNav1(totalInputAmount);
        nonNotionTokenStrategy.craftRemainingAmounts(remainingAmounts);

        vm.prank(roles.operator);
        strategyContainer.enterStrategy(address(nonNotionTokenStrategy), inputAmounts, 0);

        assertEq(
            strategyContainer.validateEnterStrategy(address(nonNotionTokenStrategy)),
            true,
            "test_EnterStrategyWithRemainder: Strategy not entered"
        );
        for (uint256 i = 0; i < inputTokens.length; i++) {
            assertEq(
                IERC20(inputTokens[i]).balanceOf(address(strategyContainer)),
                remainingAmounts[i],
                "test_EnterStrategyWithRemainder: Container should have remaining amounts"
            );
            assertEq(
                IERC20(inputTokens[i]).balanceOf(address(nonNotionTokenStrategy)),
                inputAmounts[i] - remainingAmounts[i],
                "test_EnterStrategyWithRemainder: Strategy should have input minus remaining"
            );
        }
    }

    function test_RevertIf_NotStrategy() public {
        vm.prank(roles.operator);
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.enterStrategy(makeAddr("RANDOM_ADDRESS"), new uint256[](0), 0);
    }

    function test_RevertIf_StrategyNavUnresolved() public {
        vm.prank(address(notionTokenStrategy));
        strategyContainer.startEmergencyResolution();

        vm.prank(roles.operator);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyContainer.StrategyNavUnresolved.selector, address(notionTokenStrategy))
        );
        strategyContainer.enterStrategy(address(notionTokenStrategy), new uint256[](0), 0);
    }

    function test_RevertIf_StrategyAlreadyEntered() public {
        uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
        MockERC20(address(notion)).mint(address(strategyContainer), inputAmount);
        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = inputAmount;

        notionTokenStrategy.craftNav0(0);
        notionTokenStrategy.craftNav1(inputAmount);

        vm.prank(roles.operator);
        strategyContainer.enterStrategy(address(notionTokenStrategy), inputAmounts, 0);
        vm.prank(roles.operator);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyContainer.StrategyAlreadyEntered.selector, address(notionTokenStrategy))
        );
        strategyContainer.enterStrategy(address(notionTokenStrategy), inputAmounts, 0);
    }

    function test_RevertIf_IncorrectArrayLength() public {
        nonNotionTokenStrategy.setInputTokens(new address[](2));

        vm.prank(roles.operator);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        strategyContainer.enterStrategy(address(nonNotionTokenStrategy), new uint256[](1), 0);
    }

    function test_RevertIf_StrategyReturnsRemainingAmountsWithWrongLength() public {
        address[] memory inputTokens = nonNotionTokenStrategy.getInputTokens();
        uint256[] memory inputAmounts = new uint256[](inputTokens.length);
        uint256 totalInputAmount = 0;
        for (uint256 i = 0; i < inputTokens.length; i++) {
            uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
            MockERC20(inputTokens[i]).mint(address(strategyContainer), inputAmount);
            inputAmounts[i] = inputAmount;
            totalInputAmount += inputAmount;
        }

        nonNotionTokenStrategy.craftNav0(0);
        nonNotionTokenStrategy.craftNav1(totalInputAmount);
        nonNotionTokenStrategy.craftRemainingAmounts(new uint256[](inputTokens.length + 1));

        vm.prank(roles.operator);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        strategyContainer.enterStrategy(address(nonNotionTokenStrategy), inputAmounts, 0);
    }

    function test_RevertIf_IncorrectEnterNav() public {
        uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
        MockERC20(address(notion)).mint(address(strategyContainer), inputAmount);
        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = inputAmount;

        notionTokenStrategy.craftNav0(100e18);
        notionTokenStrategy.craftNav1(50e18);

        vm.prank(roles.operator);
        vm.expectRevert(abi.encodeWithSelector(IStrategyContainer.IncorrectEnterNav.selector, 100e18, 50e18));
        strategyContainer.enterStrategy(address(notionTokenStrategy), inputAmounts, 0);
    }

    function test_RevertIf_IncorrectEnterNav_EqualNavs() public {
        uint256 inputAmount = vm.randomUint(1e18, 1000000e18);
        MockERC20(address(notion)).mint(address(strategyContainer), inputAmount);
        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = inputAmount;

        notionTokenStrategy.craftNav0(100e18);
        notionTokenStrategy.craftNav1(100e18);

        vm.prank(roles.operator);
        vm.expectRevert(abi.encodeWithSelector(IStrategyContainer.IncorrectEnterNav.selector, 100e18, 100e18));
        strategyContainer.enterStrategy(address(notionTokenStrategy), inputAmounts, 0);
    }
}
