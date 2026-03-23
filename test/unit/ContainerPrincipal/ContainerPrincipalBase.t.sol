// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";

import {Codec} from "contracts/libraries/Codec.sol";
import {Common} from "contracts/libraries/Common.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {L1Base} from "test/L1Base.t.sol";
import {Utils} from "test/Utils.sol";

contract ContainerPrincipalBaseTest is L1Base {
    using stdStorage for StdStorage;

    uint256 internal constant EXPECTED_TOKEN_AMOUNT_SLOT = 10;

    function setUp() public virtual override {
        super.setUp();

        containerPrincipal = _deployContainerPrincipal();
        _addContainer(address(containerPrincipal), REMOTE_CHAIN_ID);

        vm.prank(roles.messengerManager);
        containerPrincipal.setPeerContainer(makeAddr("ContainerAgent"));

        vm.prank(roles.bridgeAdapterManager);
        containerPrincipal.setBridgeAdapter(address(bridgeAdapter), true);

        vm.startPrank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(address(containerPrincipal));
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(dai));
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(containerPrincipal));
        vm.stopPrank();
    }

    function test_ContainerTypeIsPrincipal() public view {
        assertEq(
            uint256(containerPrincipal.containerType()),
            uint256(IContainer.ContainerType.Principal),
            "test_ContainerTypeIsPrincipal: container type mismatch"
        );
    }

    function _prepareDepositRequestData(
        uint256 depositAmount
    )
        internal
        view
        returns (
            ICrossChainContainer.MessageInstruction memory,
            address[] memory,
            IBridgeAdapter.BridgeInstruction[] memory
        )
    {
        ICrossChainContainer.MessageInstruction memory messageInstruction = ICrossChainContainer.MessageInstruction({
            value: 0,
            adapter: address(messageAdapter),
            parameters: ""
        });

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions = new IBridgeAdapter.BridgeInstruction[](1);
        bridgeInstructions[0] = IBridgeAdapter.BridgeInstruction({
            value: 0,
            chainTo: REMOTE_CHAIN_ID,
            amount: depositAmount,
            minTokenAmount: Utils.calculateMinBridgeAmount(address(containerPrincipal), depositAmount),
            token: address(notion),
            payload: ""
        });

        return (messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function _craftDepositResponseMessageSingleToken(
        address token,
        uint256 amount,
        uint256 nav0,
        uint256 nav1
    ) internal view returns (bytes memory) {
        uint256 length;
        address decimalsToken;
        if (token == address(0)) {
            length = 0;
            decimalsToken = address(notion);
        } else {
            decimalsToken = token;
            length = 1;
        }
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        if (length > 0) {
            tokens[0] = token;
            amounts[0] = Common.toUnifiedDecimalsUint8(decimalsToken, amount);
        }
        return
            Codec.encode(
                Codec.DepositResponse(
                    tokens,
                    amounts,
                    Common.toUnifiedDecimalsUint8(decimalsToken, nav0),
                    Common.toUnifiedDecimalsUint8(decimalsToken, nav1)
                )
            );
    }

    function _craftDepositResponseMessageMultipleTokens(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 nav0,
        uint256 nav1
    ) internal view returns (bytes memory) {
        require(tokens.length == amounts.length, Errors.ArrayLengthMismatch());
        for (uint256 i = 0; i < amounts.length; ++i) {
            amounts[i] = Common.toUnifiedDecimalsUint8(address(tokens[i]), amounts[i]);
        }
        return
            Codec.encode(
                Codec.DepositResponse(
                    tokens,
                    amounts,
                    Common.toUnifiedDecimalsUint8(address(tokens[0]), nav0),
                    Common.toUnifiedDecimalsUint8(address(tokens[0]), nav1)
                )
            );
    }

    function _craftWithdrawalResponseMessageSingleToken(
        address token,
        uint256 amount
    ) internal view returns (bytes memory) {
        uint256 length = token == address(0) ? 0 : 1;
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        if (length > 0) {
            tokens[0] = token;
            amounts[0] = Common.toUnifiedDecimalsUint8(address(token), amount);
        }
        return Codec.encode(Codec.WithdrawalResponse(tokens, amounts));
    }

    function _craftWithdrawalResponseMessageMultipleTokens(
        address[] memory tokens,
        uint256[] memory amounts
    ) internal view returns (bytes memory) {
        for (uint256 i = 0; i < amounts.length; ++i) {
            amounts[i] = Common.toUnifiedDecimalsUint8(address(tokens[i]), amounts[i]);
        }
        return Codec.encode(Codec.WithdrawalResponse(tokens, amounts));
    }

    function _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus status) internal {
        stdstore.target(address(containerPrincipal)).sig(containerPrincipal.status.selector).checked_write(
            uint256(status)
        );
    }
}
