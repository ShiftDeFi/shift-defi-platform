// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {BridgeAdapterBase} from "test/unit/BridgeAdapter/BridgeAdapterBase.t.sol";

contract BridgeAdapterConfigurationTest is BridgeAdapterBase {
    function setUp() public override {
        super.setUp();
    }

    function test_SetSlippageCapPct() public {
        uint256 slippageCapPct = 1234;

        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setSlippageCapPct(slippageCapPct);
        assertEq(bridgeAdapter.slippageCapPct(), slippageCapPct, "test_SetSlippageCapPct: Incorrect slippage cap pct");
    }

    function test_RevertIf_SetSlippageCapPct_ExceedsMax() public {
        vm.expectRevert(Errors.IncorrectAmount.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setSlippageCapPct(MAX_SLIPPAGE_CAP_PCT + 1);
    }

    function test_RevertIf_SetSlippageCapPct_NotBridgeAdapterManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                users.alice,
                BRIDGE_ADAPTER_MANAGER_ROLE
            )
        );
        vm.prank(users.alice);
        bridgeAdapter.setSlippageCapPct(1234);
    }

    function test_SetBridgePath() public {
        assertEq(
            bridgeAdapter.bridgePaths(address(notion), REMOTE_CHAIN_ID),
            address(0),
            "test_SetBridgePath: Incorrect bridge path before setBridgePath"
        );
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(dai));
        assertEq(
            bridgeAdapter.bridgePaths(address(notion), REMOTE_CHAIN_ID),
            address(dai),
            "test_SetBridgePath: Incorrect bridge path after setBridgePath"
        );

        vm.expectRevert(Errors.AlreadySet.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(dai));
    }

    function test_RevertIf_SetBridgePath_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setBridgePath(address(0), REMOTE_CHAIN_ID, address(dai));
    }

    function test_RevertIf_SetBridgePath_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setBridgePath(address(notion), 0, address(dai));
    }

    function test_SetPeer() public {
        address peer = makeAddr("Peer");

        assertEq(bridgeAdapter.peers(REMOTE_CHAIN_ID), address(0));
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, peer);
        assertEq(bridgeAdapter.peers(REMOTE_CHAIN_ID), peer, "test_SetPeer: Incorrect peer after setPeer");

        vm.expectRevert(Errors.AlreadySet.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, peer);
    }

    function test_RevertIf_SetPeer_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(0));
    }

    function test_RevertIf_SetPeer_ZeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.setPeer(0, address(dai));
    }

    function test_WhitelistBridger() public {
        assertEq(
            bridgeAdapter.whitelistedBridgers(BRIDGER),
            false,
            "test_WhitelistBridger: Incorrect whitelisted status before whitelistBridger"
        );
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(BRIDGER);
        assertEq(
            bridgeAdapter.whitelistedBridgers(BRIDGER),
            true,
            "test_WhitelistBridger: Incorrect whitelisted status after whitelistBridger"
        );

        vm.expectRevert(Errors.AlreadyWhitelisted.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(BRIDGER);
    }

    function test_RevertIf_WhitelistBridger_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(address(0));
    }

    function test_BlacklistBridger() public {
        vm.expectRevert(Errors.AlreadyBlacklisted.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.blacklistBridger(BRIDGER);

        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(BRIDGER);

        assertEq(bridgeAdapter.whitelistedBridgers(BRIDGER), true);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.blacklistBridger(BRIDGER);
        assertEq(
            bridgeAdapter.whitelistedBridgers(BRIDGER),
            false,
            "test_BlacklistBridger: Incorrect whitelisted status after blacklistBridger"
        );
    }

    function test_RevertIf_BlacklistBridger_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.bridgeAdapterManager);
        bridgeAdapter.blacklistBridger(address(0));
    }
}
