// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {Common} from "contracts/libraries/Common.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {CrossChainContainerBaseTest} from "test/unit/CrossChainContainer/CrossChainContainerBase.t.sol";

contract CrossChainContainerMessageTest is CrossChainContainerBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SetMessageRouter() public {
        address newMessageRouter = address(_deployMockMessageRouter(MAX_CACHE_SIZE));
        vm.prank(roles.messengerManager);
        crossChainContainer.setMessageRouter(newMessageRouter);
        assertEq(
            crossChainContainer.messageRouter(),
            newMessageRouter,
            "test_SetMessageRouter: message router mismatch"
        );
    }

    function test_RevertIf_SetMessageRouterToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.messengerManager);
        crossChainContainer.setMessageRouter(address(0));
    }

    function test_SetPeerContainer() public {
        address newPeerContainer = makeAddr("PeerContainer");
        vm.prank(roles.messengerManager);
        crossChainContainer.setPeerContainer(newPeerContainer);
        assertEq(
            crossChainContainer.peerContainer(),
            newPeerContainer,
            "test_SetPeerContainer: peer container mismatch"
        );
    }

    function test_RevertIf_SetPeerContainerToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.messengerManager);
        crossChainContainer.setPeerContainer(address(0));
    }

    function test_RevertIf_SetPeerContainerSecondTime() public {
        address newPeerContainer = makeAddr("PeerContainer");
        vm.prank(roles.messengerManager);
        crossChainContainer.setPeerContainer(newPeerContainer);

        vm.expectRevert(ICrossChainContainer.PeerContainerAlreadySet.selector);
        vm.prank(roles.messengerManager);
        crossChainContainer.setPeerContainer(newPeerContainer);
    }

    function test_ProcessExpectedTokens() public {
        vm.prank(roles.tokenManager);
        crossChainContainer.whitelistToken(address(dai));

        uint256 claimCounterBefore = crossChainContainer.claimCounter();
        uint256 tokenLength = 2;
        uint256 notionAmount = 1_000_000 * NOTION_PRECISION;
        uint256 daiAmount = 1_000_000 * DAI_PRECISION;

        address[] memory tokens = new address[](tokenLength);
        tokens[0] = address(notion);
        tokens[1] = address(dai);
        uint256[] memory amounts = new uint256[](tokenLength);
        amounts[0] = Common.toUnifiedDecimalsUint8(address(notion), notionAmount);
        amounts[1] = Common.toUnifiedDecimalsUint8(address(dai), daiAmount);

        crossChainContainer.processExpectedTokens(tokens, amounts);
        assertEq(
            crossChainContainer.claimCounter(),
            claimCounterBefore + tokenLength,
            "test_ProcessExpectedTokens: claim counter mismatch"
        );

        uint256 expectedTokenAmountNotion = _getAddressUintMappingValue(
            address(crossChainContainer),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(notion)
        );
        assertEq(
            expectedTokenAmountNotion,
            notionAmount,
            "test_ProcessExpectedTokens: expected token amount notion mismatch"
        );

        uint256 expectedTokenAmountDai = _getAddressUintMappingValue(
            address(crossChainContainer),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(dai)
        );
        assertEq(expectedTokenAmountDai, daiAmount, "test_ProcessExpectedTokens: expected token amount dai mismatch");
    }

    function test_ProcessExpectedTokensWithDuplicatingToken() public {
        vm.prank(roles.tokenManager);
        crossChainContainer.whitelistToken(address(dai));

        uint256 claimCounterBefore = crossChainContainer.claimCounter();
        uint256 tokenLength = 2;
        uint256 notionAmount = 1_000_000 * NOTION_PRECISION;

        address[] memory tokens = new address[](tokenLength);
        tokens[0] = address(notion);
        tokens[1] = address(notion);
        uint256[] memory amounts = new uint256[](tokenLength);
        amounts[0] = Common.toUnifiedDecimalsUint8(address(notion), notionAmount);
        amounts[1] = Common.toUnifiedDecimalsUint8(address(notion), notionAmount);

        crossChainContainer.processExpectedTokens(tokens, amounts);
        uint256 expectedTokenAmount = _getAddressUintMappingValue(
            address(crossChainContainer),
            EXPECTED_TOKEN_AMOUNT_SLOT,
            address(notion)
        );

        assertEq(
            crossChainContainer.claimCounter(),
            claimCounterBefore + 1,
            "test_ProcessExpectedTokensWithDuplicatingToken: claim counter mismatch"
        );
        assertEq(
            expectedTokenAmount,
            notionAmount * 2,
            "test_ProcessExpectedTokensWithDuplicatingToken: expected token amount mismatch"
        );
    }

    function test_RevertIf_ProcessExpectedTokensWithDifferentLengths() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(notion);
        tokens[1] = address(dai);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = Common.toUnifiedDecimalsUint8(address(notion), 1_000_000 * NOTION_PRECISION);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        crossChainContainer.processExpectedTokens(tokens, amounts);
    }

    function test_RevertIf_ProcessExpectedTokensWithNotWhitelistedToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(dai);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = Common.toUnifiedDecimalsUint8(address(dai), 1_000_000 * DAI_PRECISION);

        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, address(dai)));
        crossChainContainer.processExpectedTokens(tokens, amounts);
    }

    function test_RevertIf_ProcessExpectedTokensWithZeroAmount() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(notion);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.expectRevert(Errors.ZeroAmount.selector);
        crossChainContainer.processExpectedTokens(tokens, amounts);
    }
}
