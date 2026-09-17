// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {L1Base} from "test/L1Base.t.sol";

import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract ReshufflingGatewayCowProtocolTest is L1Base {
    ICowProtocolModule internal cowModule;
    MockCowProtocolAdapter internal adapter;
    MockERC20 internal buyToken;

    uint256 internal constant SELL_AMOUNT = 100e18;

    function setUp() public override {
        super.setUp();

        cowModule = ICowProtocolModule(address(reshufflingGateway));
        adapter = new MockCowProtocolAdapter(address(cowModule));
        buyToken = new MockERC20("Buy", "BUY", 6);

        vm.startPrank(roles.tokenManager);
        cowModule.setCowAdapter(address(adapter));
        reshufflingGateway.whitelistToken(address(notion));
        reshufflingGateway.whitelistToken(address(buyToken));
        vm.stopPrank();

        deal(address(notion), address(reshufflingGateway), SELL_AMOUNT);
    }

    function _params() internal view returns (ICowProtocolAdapter.OrderParams memory) {
        return
            ICowProtocolAdapter.OrderParams({
                sellToken: address(notion),
                buyToken: address(buyToken),
                sellAmount: SELL_AMOUNT,
                buyAmount: 1,
                validTo: uint32(block.timestamp + 1 hours),
                appData: bytes32(0)
            });
    }

    function _enableReshufflingMode() internal {
        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();
    }

    function _expectUnauthorized(address caller, string memory role) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                caller,
                keccak256(bytes(role))
            )
        );
        vm.prank(caller);
    }

    function test_PlaceCowOrder() public {
        _enableReshufflingMode();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = cowModule.placeCowOrder(_params());

        assertEq(orderDigest, keccak256(abi.encode(_params())));
    }

    function test_CancelCowOrder_OutsideReshufflingMode() public {
        _enableReshufflingMode();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = cowModule.placeCowOrder(_params());

        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        vm.expectCall(address(adapter), abi.encodeCall(ICowProtocolAdapter.cancelOrder, (orderDigest)));
        vm.prank(roles.reshufflingExecutor);
        cowModule.cancelCowOrder(orderDigest);
    }

    function test_ResolveCowOrder_OutsideReshufflingMode() public {
        _enableReshufflingMode();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = cowModule.placeCowOrder(_params());

        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        vm.expectCall(address(adapter), abi.encodeCall(ICowProtocolAdapter.resolveOrder, (orderDigest)));
        vm.prank(roles.reshufflingExecutor);
        cowModule.resolveCowOrder(orderDigest);
    }

    function test_RevertIf_PlaceCowOrder_NotInReshufflingMode() public {
        vm.expectRevert(Errors.ReshufflingModeDisabled.selector);
        vm.prank(roles.reshufflingExecutor);
        cowModule.placeCowOrder(_params());
    }

    function test_RevertIf_PlaceCowOrder_CallerNotReshufflingExecutor() public {
        _enableReshufflingMode();

        _expectUnauthorized(roles.tokenManager, "RESHUFFLING_EXECUTOR_ROLE");
        cowModule.placeCowOrder(_params());
    }

    function test_RevertIf_CancelCowOrder_CallerNotReshufflingExecutor() public {
        _expectUnauthorized(roles.tokenManager, "RESHUFFLING_EXECUTOR_ROLE");
        cowModule.cancelCowOrder(bytes32(0));
    }

    function test_RevertIf_ResolveCowOrder_CallerNotReshufflingExecutor() public {
        _expectUnauthorized(roles.tokenManager, "RESHUFFLING_EXECUTOR_ROLE");
        cowModule.resolveCowOrder(bytes32(0));
    }

    function test_RevertIf_SetCowAdapter_CallerNotTokenManager() public {
        _expectUnauthorized(roles.reshufflingExecutor, "TOKEN_MANAGER_ROLE");
        cowModule.setCowAdapter(address(adapter));
    }

    function test_RevertIf_SweepCowAdapter_CallerNotTokenManager() public {
        _expectUnauthorized(roles.reshufflingExecutor, "TOKEN_MANAGER_ROLE");
        cowModule.sweepCowAdapter(address(notion));
    }

    function test_RevertIf_SweepCowLane_CallerNotTokenManager() public {
        _expectUnauthorized(roles.reshufflingExecutor, "TOKEN_MANAGER_ROLE");
        cowModule.sweepCowLane(0, address(notion));
    }

    function test_BlacklistToken() public {
        vm.prank(roles.tokenManager);
        reshufflingGateway.blacklistToken(address(buyToken));

        assertEq(cowModule.pendingCowOrderCount(), 0);
    }

    function test_RevertIf_BlacklistToken_OrdersStillPending() public {
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.tokenManager);
        reshufflingGateway.blacklistToken(address(buyToken));
    }

    /// @dev The gateway keeps no dust thresholds, so any balance blocks the removal.
    function test_RevertIf_BlacklistToken_BalanceNotZero() public {
        deal(address(buyToken), address(reshufflingGateway), 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.TokenBalanceNotDust.selector, address(buyToken), 1));
        vm.prank(roles.tokenManager);
        reshufflingGateway.blacklistToken(address(buyToken));
    }

    function test_RevertIf_BlacklistToken_FillDeliveredWhileResolving() public {
        adapter.setPendingOrderCount(1);
        deal(address(buyToken), address(adapter), 1e6);
        adapter.setFillOnRequire(address(buyToken), 1e6);

        vm.expectRevert(abi.encodeWithSelector(Errors.TokenBalanceNotDust.selector, address(buyToken), 1e6));
        vm.prank(roles.tokenManager);
        reshufflingGateway.blacklistToken(address(buyToken));
    }
}
