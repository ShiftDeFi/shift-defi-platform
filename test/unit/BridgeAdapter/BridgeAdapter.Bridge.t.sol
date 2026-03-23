// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {RingCacheLib} from "contracts/libraries/RingCacheLib.sol";
import {BridgeAdapterBase} from "test/unit/BridgeAdapter/BridgeAdapterBase.t.sol";

contract BridgeAdapterBridgeTest is BridgeAdapterBase {
    function setUp() public override {
        super.setUp();

        vm.startPrank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(users.alice);
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(notion));
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(this));
        vm.stopPrank();
    }

    function test_Bridge() public {
        address receiver = makeAddr("Receiver");
        uint256 nonce = 0;

        notion.mint(users.alice, BRIDGE_AMOUNT);
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        uint256 balanceBefore = IERC20(address(notion)).balanceOf(users.alice);
        uint256 adapterBalanceBefore = IERC20(address(notion)).balanceOf(address(bridgeAdapter));
        vm.startPrank(users.alice);
        IERC20(address(notion)).approve(address(bridgeAdapter), BRIDGE_AMOUNT);
        uint256 bridgedAmount = bridgeAdapter.bridge(instruction, receiver);
        vm.stopPrank();
        uint256 balanceAfter = IERC20(address(notion)).balanceOf(users.alice);
        uint256 adapterBalanceAfter = IERC20(address(notion)).balanceOf(address(bridgeAdapter));

        assertEq(bridgedAmount, BRIDGE_AMOUNT, "test_Bridge: Incorrect bridged amount");
        assertEq(balanceBefore - balanceAfter, BRIDGE_AMOUNT, "test_Bridge: Incorrect balance before and after");
        assertEq(
            adapterBalanceAfter - adapterBalanceBefore,
            BRIDGE_AMOUNT,
            "test_Bridge: Incorrect adapter balance before and after"
        );
        assertTrue(
            bridgeAdapter.isCached(address(notion), REMOTE_CHAIN_ID, BRIDGE_AMOUNT, receiver, nonce),
            "test_Bridge: bridge not cached"
        );
    }

    function test_Bridge_UsesLeftoverNativeBalanceWhenMsgValueIsZero() public {
        address receiver = makeAddr("Receiver");

        notion.mint(users.alice, BRIDGE_AMOUNT * 2);
        vm.deal(users.alice, 1);
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        instruction.value = 1;

        vm.startPrank(users.alice);
        IERC20(address(notion)).approve(address(bridgeAdapter), BRIDGE_AMOUNT * 2);
        bridgeAdapter.bridge{value: 1}(instruction, receiver);
        bridgeAdapter.bridge(instruction, receiver);
        vm.stopPrank();
    }

    function test_RevertIf_Bridge_ZeroReceiver() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, address(0));
    }

    function test_RevertIf_Bridge_NotWhitelistedBridger() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.BridgerNotWhitelisted.selector, address(this)));
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RetryBridge() public {
        address receiver = makeAddr("Receiver");
        uint256 nonce = 0;

        notion.mint(users.alice, BRIDGE_AMOUNT);
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.startPrank(users.alice);
        IERC20(address(notion)).approve(address(bridgeAdapter), BRIDGE_AMOUNT);
        bridgeAdapter.bridge(instruction, receiver);

        bridgeAdapter.retryBridge(instruction, receiver, nonce);
        vm.stopPrank();
    }

    function test_RevertIf_RetryBridge_NotCached() public {
        address receiver = makeAddr("Receiver");
        uint256 nonce = 0;
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBridgeAdapter.BridgeInstructionNotCached.selector,
                bytes32("BRIDGE_CACHE"),
                keccak256(abi.encode(instruction.token, instruction.chainTo, instruction.amount, receiver, nonce))
            )
        );
        vm.prank(users.alice);
        bridgeAdapter.retryBridge(instruction, receiver, nonce);
    }

    function test_RevertIf_RetryBridge_NotWhitelistedBridger() public {
        uint256 nonce = 0;
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.BridgerNotWhitelisted.selector, address(this)));
        bridgeAdapter.retryBridge(instruction, makeAddr("Receiver"), nonce);
    }

    function test_RevertIf_ValidateBridgeInstruction_ZeroToken() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(0), BRIDGE_AMOUNT);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RevertIf_ValidateBridgeInstruction_ZeroChainTo() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        instruction.chainTo = 0;

        vm.expectRevert(abi.encodeWithSelector(Errors.IncorrectChainId.selector, 0));
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RevertIf_ValidateBridgeInstruction_ZeroAmount() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), 0);

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RevertIf_ValidateBridgeInstruction_BadBridgePath() public {
        MockERC20 unknownToken = new MockERC20("Unknown", "UNK", 18);

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(
            address(unknownToken),
            BRIDGE_AMOUNT
        );

        vm.expectRevert(
            abi.encodeWithSelector(IBridgeAdapter.BadBridgePath.selector, address(unknownToken), REMOTE_CHAIN_ID)
        );
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RevertIf_ValidateBridgeInstruction_PeerNotSet() public {
        uint256 unknownChainId = 999999;

        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setBridgePath(address(notion), unknownChainId, address(notion));

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        instruction.chainTo = unknownChainId;

        vm.expectRevert(abi.encodeWithSelector(IBridgeAdapter.PeerNotSet.selector, unknownChainId));
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RevertIf_ValidateBridgeInstruction_MinTokenAmountExceedsAmount() public {
        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        instruction.minTokenAmount = BRIDGE_AMOUNT + 1;

        vm.expectRevert(Errors.IncorrectAmount.selector);
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }

    function test_RevertIf_ValidateBridgeInstruction_SlippageCapExceeded() public {
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setSlippageCapPct(100);

        IBridgeAdapter.BridgeInstruction memory instruction = _craftBridgeInstruction(address(notion), BRIDGE_AMOUNT);

        uint256 slippageDelta = instruction.amount - instruction.minTokenAmount;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBridgeAdapter.SlippageCapExceeded.selector,
                slippageDelta,
                bridgeAdapter.slippageCapPct()
            )
        );
        vm.prank(users.alice);
        bridgeAdapter.bridge(instruction, makeAddr("Receiver"));
    }
}
