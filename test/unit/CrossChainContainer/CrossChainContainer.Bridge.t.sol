// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {Common} from "contracts/libraries/helpers/Common.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {FaultyBridgeAdapter} from "test/mocks/FaultyBridgeAdapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {CrossChainContainerBaseTest} from "test/unit/CrossChainContainer/CrossChainContainerBase.t.sol";

contract CrossChainContainerBridgeTest is CrossChainContainerBaseTest {
    using Math for uint256;

    address internal bridgeReceiver;
    uint256 internal constant BRIDGE_AMOUNT = 1_000_000 * NOTION_PRECISION;

    function setUp() public virtual override {
        super.setUp();
        bridgeReceiver = makeAddr("BRIDGE_RECEIVER");
    }

    function _prepareTokensToClaim(address _bridgeAdapter, address[] memory tokens, uint256[] memory amounts) internal {
        if (!crossChainContainer.isBridgeAdapterSupported(_bridgeAdapter)) {
            vm.prank(roles.bridgeAdapterManager);
            crossChainContainer.setBridgeAdapter(_bridgeAdapter, true);
        }

        uint256[] memory amountInUnifiedDecimals = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (!crossChainContainer.isTokenWhitelisted(tokens[i])) {
                vm.prank(roles.tokenManager);
                crossChainContainer.whitelistToken(tokens[i]);
            }
            MockERC20(tokens[i]).mint(_bridgeAdapter, amounts[i]);
            bridgeAdapter.finalizeBridge(address(crossChainContainer), tokens[i], amounts[i]);
            amountInUnifiedDecimals[i] = Common.toUnifiedDecimalsUint8(tokens[i], amounts[i]);
        }

        crossChainContainer.processExpectedTokens(tokens, amountInUnifiedDecimals);
    }

    function test_SetBridgeAdapter() public {
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);
        assertEq(
            crossChainContainer.isBridgeAdapterSupported(address(bridgeAdapter)),
            true,
            "test_SetBridgeAdapter: bridge adapter not supported"
        );
    }

    function test_RevertIf_SetBridgeAdapterWithZeroAddress() public {
        vm.prank(roles.bridgeAdapterManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        crossChainContainer.setBridgeAdapter(address(0), true);
    }

    function test_RevertIf_SetBridgeAdapterToTheSameStatus() public {
        vm.expectRevert(ICrossChainContainer.SameBridgeAdapterStatus.selector);
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), false);

        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);

        vm.expectRevert(ICrossChainContainer.SameBridgeAdapterStatus.selector);
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);
    }

    function test_ClaimExpectedToken() public {
        uint256 tokenLength = 2;
        address[] memory tokens = new address[](tokenLength);
        tokens[0] = address(notion);
        tokens[1] = address(dai);
        uint256[] memory amounts = new uint256[](tokenLength);
        amounts[0] = 1_000_000 * NOTION_PRECISION;
        amounts[1] = 1_000_000 * DAI_PRECISION;

        _prepareTokensToClaim(address(bridgeAdapter), tokens, amounts);

        uint256 claimCounterBefore = crossChainContainer.claimCounter();
        uint256 notionBalanceBefore = IERC20(address(notion)).balanceOf(address(crossChainContainer));

        crossChainContainer.claimExpectedToken(address(bridgeAdapter), address(notion));

        assertEq(
            notion.balanceOf(address(crossChainContainer)),
            notionBalanceBefore + amounts[0],
            "test_ClaimExpectedToken: notion balance mismatch on CrossChainContainer"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            0,
            "test_ClaimExpectedToken: notion balance mismatch on BridgeAdapter"
        );

        assertEq(
            crossChainContainer.claimCounter(),
            claimCounterBefore - 1,
            "test_ClaimExpectedToken: claim counter mismatch for notion"
        );

        uint256 expectedTokenAmountNotion = _getAddressUintMappingValue(
            address(crossChainContainer),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(notion)
        );
        assertEq(expectedTokenAmountNotion, 0, "test_ClaimExpectedToken: expected token amount notion mismatch");

        uint256 daiBalanceBefore = IERC20(address(dai)).balanceOf(address(crossChainContainer));
        crossChainContainer.claimExpectedToken(address(bridgeAdapter), address(dai));

        assertEq(
            dai.balanceOf(address(crossChainContainer)),
            daiBalanceBefore + amounts[1],
            "test_ClaimExpectedToken: dai balance mismatch on CrossChainContainer"
        );
        assertEq(
            dai.balanceOf(address(bridgeAdapter)),
            0,
            "test_ClaimExpectedToken: dai balance mismatch on BridgeAdapter"
        );
        assertEq(crossChainContainer.claimCounter(), 0, "test_ClaimExpectedToken: claim counter mismatch for dai");

        uint256 expectedTokenAmountDai = _getAddressUintMappingValue(
            address(crossChainContainer),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(dai)
        );
        assertEq(expectedTokenAmountDai, 0, "test_ClaimExpectedToken: expected token amount dai mismatch");
    }

    function test_RevertIf_ClaimExpectedTokenWithoutExpectedTokens() public {
        vm.expectRevert(ICrossChainContainer.NotExpectingTokens.selector);
        crossChainContainer.claimExpectedToken(address(bridgeAdapter), address(notion));
    }

    function test_RevertIf_ClaimExpectedTokenWithInvalidBridgeAdapter() public {
        uint256 tokenLength = 1;
        address[] memory tokens = new address[](tokenLength);
        tokens[0] = address(notion);
        uint256[] memory amounts = new uint256[](tokenLength);
        amounts[0] = 1_000_000 * NOTION_PRECISION;

        _prepareTokensToClaim(address(bridgeAdapter), tokens, amounts);

        vm.expectRevert(Errors.ZeroAddress.selector);
        crossChainContainer.claimExpectedToken(address(0), address(notion));

        vm.expectRevert(ICrossChainContainer.BridgeAdapterNotSupported.selector);
        crossChainContainer.claimExpectedToken(makeAddr("invalidBridgeAdapter"), address(notion));
    }

    function test_RevertIf_ClaimExpectedTokenWithInvalidToken() public {
        uint256 tokenLength = 1;
        address[] memory tokens = new address[](tokenLength);
        tokens[0] = address(notion);
        uint256[] memory amounts = new uint256[](tokenLength);
        amounts[0] = 1_000_000 * NOTION_PRECISION;

        _prepareTokensToClaim(address(bridgeAdapter), tokens, amounts);

        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(dai)));
        crossChainContainer.claimExpectedToken(address(bridgeAdapter), address(dai));

        vm.prank(roles.tokenManager);
        crossChainContainer.whitelistToken(address(dai));

        vm.expectRevert(ICrossChainContainer.TokenNotExpected.selector);
        crossChainContainer.claimExpectedToken(address(bridgeAdapter), address(dai));
    }

    function test_RevertIf_ClaimExpectedTokenWithInsufficientBridgeAmount() public {
        uint256 tokenLength = 1;
        address[] memory tokens = new address[](tokenLength);
        tokens[0] = address(notion);
        uint256[] memory amounts = new uint256[](tokenLength);
        amounts[0] = 1_000_000 * NOTION_PRECISION;
        uint256[] memory amountInUnifiedDecimals = new uint256[](tokenLength);
        amountInUnifiedDecimals[0] = Common.toUnifiedDecimalsUint8(tokens[0], amounts[0]);

        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);

        crossChainContainer.processExpectedTokens(tokens, amountInUnifiedDecimals);

        uint256 incorrectAmount = amounts[0] - 1;
        MockERC20(tokens[0]).mint(address(bridgeAdapter), incorrectAmount);
        bridgeAdapter.finalizeBridge(address(crossChainContainer), tokens[0], incorrectAmount);

        vm.expectRevert(
            abi.encodeWithSelector(ICrossChainContainer.InsufficientBridgeAmount.selector, amounts[0], incorrectAmount)
        );
        crossChainContainer.claimExpectedToken(address(bridgeAdapter), address(notion));
    }

    function test_BridgeToken() public {
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        notion.mint(address(crossChainContainer), BRIDGE_AMOUNT);
        uint256 notionBalanceBefore = notion.balanceOf(address(crossChainContainer));

        (address tokenOnDestinationChain, uint256 amountInUnifiedDecimals) = crossChainContainer.bridgeToken(
            address(bridgeAdapter),
            bridgeReceiver,
            instruction
        );

        uint256 expectedNotionAmount = notionBalanceBefore > 0 ? notionBalanceBefore - BRIDGE_AMOUNT : 0;
        assertEq(tokenOnDestinationChain, address(notion), "test_BridgeToken: token on destination chain mismatch");
        assertEq(
            amountInUnifiedDecimals,
            Common.toUnifiedDecimalsUint8(address(notion), BRIDGE_AMOUNT),
            "test_BridgeToken: amount in unified decimals mismatch"
        );
        assertEq(
            notion.balanceOf(address(crossChainContainer)),
            expectedNotionAmount,
            "test_BridgeToken: notion balance mismatch on CrossChainContainer"
        );
    }

    function test_RevertIf_BridgeInvalidToken() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(dai), BRIDGE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(dai)));
        crossChainContainer.bridgeToken(address(bridgeAdapter), bridgeReceiver, instruction);
    }

    function test_RevertIf_BridgeInvalidBridgeAdapter() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.expectRevert(Errors.ZeroAddress.selector);
        crossChainContainer.bridgeToken(address(0), bridgeReceiver, instruction);

        vm.expectRevert(ICrossChainContainer.BridgeAdapterNotSupported.selector);
        crossChainContainer.bridgeToken(makeAddr("invalidBridgeAdapter"), bridgeReceiver, instruction);
    }

    function test_RevertIf_BridgeInsufficientAmount() public {
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughTokens.selector, address(notion), BRIDGE_AMOUNT));
        crossChainContainer.bridgeToken(address(bridgeAdapter), bridgeReceiver, instruction);
    }

    function test_RevertIf_BridgeInvalidMinTokenAmount() public {
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        instruction.minTokenAmount = BRIDGE_AMOUNT.mulDiv(crossChainContainer.MAX_BRIDGE_SLIPPAGE() - 1, MAX_BPS);

        notion.mint(address(crossChainContainer), BRIDGE_AMOUNT);

        vm.expectRevert(Errors.IncorrectAmount.selector);
        crossChainContainer.bridgeToken(address(bridgeAdapter), bridgeReceiver, instruction);
    }

    function test_RevertIf_IncorrectActualAmountBridged() public {
        IBridgeAdapter faultyBridgeAdapter = new FaultyBridgeAdapter();
        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(faultyBridgeAdapter), true);

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        notion.mint(address(crossChainContainer), BRIDGE_AMOUNT);

        vm.expectRevert(Errors.IncorrectAmount.selector);
        crossChainContainer.bridgeToken(address(faultyBridgeAdapter), bridgeReceiver, instruction);
    }

    function test_ValidateBridgeAdapter() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        crossChainContainer.validateBridgeAdapter(address(0));

        vm.expectRevert(ICrossChainContainer.BridgeAdapterNotSupported.selector);
        crossChainContainer.validateBridgeAdapter(makeAddr("INVALID_BRIDGE_ADAPTER"));
    }

    function test_ValidateClaimableToken() public {
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(dai)));
        crossChainContainer.validateClaimableToken(address(dai));

        vm.prank(roles.tokenManager);
        crossChainContainer.whitelistToken(address(dai));

        vm.expectRevert(ICrossChainContainer.TokenNotExpected.selector);
        crossChainContainer.validateClaimableToken(address(dai));
    }

    function test_ApproveTokenToBridgeAdapter() public {
        uint256 amount = 1_000_000 * NOTION_PRECISION;

        vm.expectRevert(ICrossChainContainer.BridgeAdapterNotSupported.selector);
        crossChainContainer.approveTokenToBridgeAdapter(address(notion), address(bridgeReceiver), amount);

        vm.prank(roles.bridgeAdapterManager);
        crossChainContainer.setBridgeAdapter(address(bridgeAdapter), true);

        vm.expectRevert(Errors.ZeroAddress.selector);
        crossChainContainer.approveTokenToBridgeAdapter(address(0), address(bridgeAdapter), amount);

        crossChainContainer.approveTokenToBridgeAdapter(address(dai), address(bridgeAdapter), amount);

        assertEq(
            IERC20(address(dai)).allowance(address(crossChainContainer), address(bridgeAdapter)),
            amount,
            "test_ApproveTokenToBridgeAdapter: allowance mismatch"
        );
    }
}
