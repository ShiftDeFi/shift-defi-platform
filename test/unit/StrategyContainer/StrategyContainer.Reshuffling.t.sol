// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyContainerReshufflingTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal mockStrategy;

    function setUp() public override {
        super.setUp();
        (mockStrategy, , ) = _createAndAddStrategyWithTokens(1, 1, true);
    }

    function test_EnableReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        assertTrue(strategyContainer.isReshufflingMode(), "test_EnableReshufflingMode: Reshuffling mode not enabled");
    }

    function test_RevertIf_EnableReshufflingInEmergencyResolution() public {
        vm.prank(address(mockStrategy));
        strategyContainer.startEmergencyResolution();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        strategyContainer.enableReshufflingMode();
    }

    function test_RevertIf_ReshufflingModeAlreadyEnabled() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IStrategyContainer.ActionUnavailableInReshufflingMode.selector);
        strategyContainer.enableReshufflingMode();
    }

    function test_RevertIf_NotReshufflingManagerCallsEnableReshufflingMode() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                RESHUFFLING_MANAGER_ROLE
            )
        );
        strategyContainer.enableReshufflingMode();
    }

    function test_RevertIf_CurrentBatchTypeNotNotAvailbleForReshuffle() public {
        strategyContainer.craftCurrentBatchType(IStrategyContainer.CurrentBatchType.DepositBatch);

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        strategyContainer.enableReshufflingMode();
    }

    function test_DisableReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        assertTrue(strategyContainer.isReshufflingMode(), "test_DisableReshufflingMode: Reshuffling mode not enabled");

        vm.prank(roles.reshufflingManager);
        strategyContainer.disableReshufflingMode();

        assertFalse(
            strategyContainer.isReshufflingMode(),
            "test_DisableReshufflingMode: Reshuffling mode not disabled"
        );
    }

    function test_RevertIf_DisableReshufflingModeNotEnabled() public {
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IStrategyContainer.ActionUnavailableNotInReshufflingMode.selector);
        strategyContainer.disableReshufflingMode();
    }

    function test_RevertIf_DisableReshufflingInEmergencyResolution() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        vm.prank(address(mockStrategy));
        strategyContainer.startEmergencyResolution();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IStrategyContainer.EmergencyResolutionInProgress.selector);
        strategyContainer.disableReshufflingMode();
    }

    function test_RevertIf_NotReshufflingManagerCallsDisableReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                RESHUFFLING_MANAGER_ROLE
            )
        );
        strategyContainer.disableReshufflingMode();
    }

    function test_RevertIf_CurrentBatchTypeNotNoBatchForDisableReshuffling() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();

        strategyContainer.craftCurrentBatchType(IStrategyContainer.CurrentBatchType.DepositBatch);

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.IncorrectContainerStatus.selector);
        strategyContainer.disableReshufflingMode();
    }

    // ---- Enter In Reshuffling Mode tests ----

    function test_EnterInReshufflingMode_WithoutRemainder() public {
        uint256[] memory inputAmounts = _craftTokenAmountsOnStrategyContainer(address(mockStrategy));
        address[] memory inputTokens = mockStrategy.getInputTokens();

        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.prank(roles.reshufflingManager);
        strategyContainer.enterInReshufflingMode(address(mockStrategy), inputAmounts, 0);

        for (uint256 i = 0; i < inputTokens.length; i++) {
            assertEq(
                IERC20(inputTokens[i]).balanceOf(address(strategyContainer)),
                0,
                "test_EnterInReshufflingMode_WithoutRemainder: Container balance should be 0"
            );
            assertEq(
                IERC20(inputTokens[i]).balanceOf(address(mockStrategy)),
                inputAmounts[i],
                "test_EnterInReshufflingMode_WithoutRemainder: Strategy balance should equal input amount"
            );
        }
    }

    function test_EnterInReshufflingMode_WithRemainder() public {
        uint256 nav1Response = vm.randomUint(1e18, 1000e18);
        uint256[] memory inputAmounts = _craftTokenAmountsOnStrategyContainer(address(mockStrategy));
        address[] memory inputTokens = mockStrategy.getInputTokens();
        uint256[] memory remainingAmounts = new uint256[](inputTokens.length);

        for (uint256 i = 0; i < inputTokens.length; i++) {
            mockStrategy.approveToken(inputTokens[i], type(uint256).max, address(strategyContainer));
            uint256 remainingShare = vm.randomUint(1, MAX_BPS);
            uint256 remainingAmount = (inputAmounts[i] * remainingShare) / MAX_BPS;
            remainingAmounts[i] = remainingAmount;
        }

        mockStrategy.craftNav1(nav1Response);
        mockStrategy.craftRemainingAmounts(remainingAmounts);

        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        strategyContainer.enterInReshufflingMode(address(mockStrategy), inputAmounts, 0);
        vm.stopPrank();

        for (uint256 i = 0; i < inputTokens.length; i++) {
            assertEq(
                IERC20(inputTokens[i]).balanceOf(address(strategyContainer)),
                remainingAmounts[i],
                "test_EnterInReshufflingMode_WithRemainder: Container should have remaining amounts"
            );
            assertEq(
                IERC20(inputTokens[i]).balanceOf(address(mockStrategy)),
                inputAmounts[i] - remainingAmounts[i],
                "test_EnterInReshufflingMode_WithRemainder: Strategy should have input minus remaining"
            );
        }
    }

    function test_RevertIf_NotReshufflingManagerCallsEnterInReshufflingMode() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        address[] memory inputTokens = mockStrategy.getInputTokens();
        uint256[] memory emptyInputAmounts = new uint256[](inputTokens.length);
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                RESHUFFLING_MANAGER_ROLE
            )
        );
        strategyContainer.enterInReshufflingMode(address(mockStrategy), emptyInputAmounts, 0);
    }

    function test_RevertIf_NotStrategyInEnterInReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.enterInReshufflingMode(makeAddr("RANDOM_ADDRESS"), new uint256[](0), 0);
    }

    function test_RevertIf_StrategyNavUnresolvedInEnterInReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.prank(address(mockStrategy));
        strategyContainer.startEmergencyResolution();
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyContainer.StrategyNavUnresolved.selector, address(mockStrategy))
        );
        strategyContainer.enterInReshufflingMode(address(mockStrategy), new uint256[](0), 0);
    }

    function test_RevertIf_IncorrectArrayLengthInEnterInReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        strategyContainer.enterInReshufflingMode(address(mockStrategy), new uint256[](2), 0);
    }

    function test_RevertIf_InputTokenNotWhitelistedInEnterInReshufflingMode() public {
        address[] memory inputTokens = new address[](1);
        inputTokens[0] = address(_deployMockERC20("Token", "TKN", 18));
        MockERC20(inputTokens[0]).mint(address(strategyContainer), 1000e18);

        mockStrategy.setInputTokens(inputTokens);

        uint256[] memory inputAmounts = new uint256[](1);
        inputAmounts[0] = 1000e18;
        uint256[] memory remainingAmounts = new uint256[](1);
        uint256 nav1Response = 999e18;

        for (uint256 i = 0; i < inputTokens.length; i++) {
            mockStrategy.approveToken(inputTokens[i], type(uint256).max, address(strategyContainer));
            uint256 remainingShare = vm.randomUint(1, MAX_BPS);
            uint256 remainingAmount = (inputAmounts[i] * remainingShare) / MAX_BPS;
            remainingAmounts[i] = remainingAmount;
        }

        mockStrategy.craftNav1(nav1Response);
        mockStrategy.craftRemainingAmounts(remainingAmounts);

        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, inputTokens[0]));
        strategyContainer.enterInReshufflingMode(address(mockStrategy), inputAmounts, 0);
        vm.stopPrank();
    }

    function test_ExitInReshufflingMode_Success() public {
        uint256 share = vm.randomUint(1, MAX_BPS);

        address[] memory outputTokens = mockStrategy.getOutputTokens();
        uint256[] memory outputAmounts = new uint256[](outputTokens.length);

        for (uint256 i = 0; i < outputTokens.length; i++) {
            outputAmounts[i] = vm.randomUint(MIN_AMOUNT, MAX_AMOUNT);
            MockERC20(outputTokens[i]).mint(address(mockStrategy), outputAmounts[i]);
            mockStrategy.approveToken(outputTokens[i], outputAmounts[i], address(strategyContainer));
        }

        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        strategyContainer.exitInReshufflingMode(address(mockStrategy), share, type(uint256).max);
        vm.stopPrank();

        for (uint256 i = 0; i < outputTokens.length; i++) {
            uint256 expectedAmount = (outputAmounts[i] * share) / MAX_BPS;
            assertEq(
                IERC20(outputTokens[i]).balanceOf(address(strategyContainer)),
                expectedAmount,
                "test_ExitInReshufflingMode_Success: Container should have expected amount"
            );
            assertEq(
                IERC20(outputTokens[i]).balanceOf(address(mockStrategy)),
                outputAmounts[i] - expectedAmount,
                "test_ExitInReshufflingMode_Success: Strategy should have remaining amount"
            );
        }
    }

    function test_ExitInReshufflingMode_WithNonWhitelistedTokens_Success() public {
        uint256 share = vm.randomUint(1, MAX_BPS);

        address nonWhitelistedToken = address(_deployMockERC20("NonWhitelisted", "NW", 18));
        address[] memory newOutputTokens = new address[](2);
        newOutputTokens[0] = address(notion);
        newOutputTokens[1] = nonWhitelistedToken;

        mockStrategy.setOutputTokens(newOutputTokens);

        uint256[] memory outputAmounts = new uint256[](newOutputTokens.length);

        for (uint256 i = 0; i < newOutputTokens.length; i++) {
            outputAmounts[i] = vm.randomUint(MIN_AMOUNT, MAX_AMOUNT);
            MockERC20(newOutputTokens[i]).mint(address(mockStrategy), outputAmounts[i]);
            mockStrategy.approveToken(newOutputTokens[i], outputAmounts[i], address(strategyContainer));
        }

        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        strategyContainer.exitInReshufflingMode(address(mockStrategy), share, type(uint256).max);
        vm.stopPrank();

        uint256 expectedAmountToken0 = (outputAmounts[0] * share) / MAX_BPS;
        assertEq(
            IERC20(newOutputTokens[0]).balanceOf(address(strategyContainer)),
            expectedAmountToken0,
            "test_ExitInReshufflingMode_WithNonWhitelistedTokens_Success: Whitelisted token should be transferred"
        );
        assertEq(
            IERC20(newOutputTokens[0]).balanceOf(address(mockStrategy)),
            outputAmounts[0] - expectedAmountToken0,
            "test_ExitInReshufflingMode_WithNonWhitelistedTokens_Success: Whitelisted token remaining in strategy"
        );

        assertEq(
            IERC20(newOutputTokens[1]).balanceOf(address(strategyContainer)),
            0,
            "test_ExitInReshufflingMode_WithNonWhitelistedTokens_Success: Non-whitelisted token should not be in container"
        );
        assertEq(
            IERC20(newOutputTokens[1]).balanceOf(address(mockStrategy)),
            outputAmounts[1],
            "test_ExitInReshufflingMode_WithNonWhitelistedTokens_Success: Non-whitelisted token should remain in strategy"
        );
    }

    function test_RevertIf_NotReshufflingManagerCallsExitInReshufflingMode() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                RESHUFFLING_MANAGER_ROLE
            )
        );
        strategyContainer.exitInReshufflingMode(address(mockStrategy), MAX_BPS, type(uint256).max);
    }

    function test_RevertIf_NotInReshufflingModeInExitInReshufflingMode() public {
        vm.startPrank(roles.reshufflingManager);
        vm.expectRevert(IStrategyContainer.ActionUnavailableNotInReshufflingMode.selector);
        strategyContainer.exitInReshufflingMode(address(mockStrategy), MAX_BPS, type(uint256).max);
        vm.stopPrank();
    }

    function test_RevertIf_NotStrategyInExitInReshufflingMode() public {
        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.exitInReshufflingMode(makeAddr("RANDOM_ADDRESS"), MAX_BPS, type(uint256).max);
        vm.stopPrank();
    }

    function test_RevertIf_StrategyNavUnresolvedInExitInReshufflingMode() public {
        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.stopPrank();

        vm.prank(address(mockStrategy));
        strategyContainer.startEmergencyResolution();

        vm.startPrank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IStrategyContainer.StrategyNavUnresolved.selector, address(mockStrategy))
        );
        strategyContainer.exitInReshufflingMode(address(mockStrategy), MAX_BPS, type(uint256).max);
        vm.stopPrank();
    }

    function test_RevertIf_ZeroShareInExitInReshufflingMode() public {
        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.expectRevert(Errors.ZeroAmount.selector);
        strategyContainer.exitInReshufflingMode(address(mockStrategy), 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_RevertIf_ShareExceedsBPSInExitInReshufflingMode() public {
        vm.startPrank(roles.reshufflingManager);
        strategyContainer.enableReshufflingMode();
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategyContainer.exitInReshufflingMode(address(mockStrategy), MAX_BPS + 1, type(uint256).max);
        vm.stopPrank();
    }
}
