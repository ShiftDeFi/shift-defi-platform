// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

import {ContainerPrincipalBaseTest} from "test/unit/ContainerPrincipal/ContainerPrincipalBase.t.sol";
import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract ContainerPrincipalCowProtocolTest is ContainerPrincipalBaseTest {
    ICowProtocolModule internal cowModule;
    MockCowProtocolAdapter internal adapter;
    MockERC20 internal buyToken;

    uint256 internal constant SELL_AMOUNT = 100e18;

    /// @dev No initializer grants this role, so every test that exercises cancel or resolve has to
    ///      grant it the way a deployment does.
    bytes32 internal constant COW_SWAP_MANAGER_ROLE = keccak256("COW_SWAP_MANAGER_ROLE");

    address internal cowSwapManager = makeAddr("cowSwapManager");

    function setUp() public override {
        super.setUp();

        cowModule = ICowProtocolModule(address(containerPrincipal));
        adapter = new MockCowProtocolAdapter(address(cowModule));
        buyToken = new MockERC20("Buy", "BUY", 6);

        vm.prank(roles.tokenManager);
        cowModule.setCowAdapter(address(adapter));

        _whitelistToken(address(containerPrincipal), address(buyToken));
        deal(address(notion), address(containerPrincipal), SELL_AMOUNT);
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

    function _grantCowSwapManager() internal {
        vm.prank(roles.defaultAdmin);
        IAccessControl(address(containerPrincipal)).grantRole(COW_SWAP_MANAGER_ROLE, cowSwapManager);
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

    function test_SetCowAdapter() public {
        assertEq(cowModule.cowAdapter(), address(adapter));
    }

    function test_PlaceCowOrder() public {
        vm.prank(roles.operator);
        bytes32 orderDigest = cowModule.placeCowOrder(_params());

        assertEq(orderDigest, keccak256(abi.encode(_params())));
    }

    function test_RevertIf_PlaceCowOrder_CallerNotOperator() public {
        _expectUnauthorized(roles.tokenManager, "OPERATOR_ROLE");
        cowModule.placeCowOrder(_params());
    }

    function test_RevertIf_PlaceCowOrder_Paused() public {
        vm.prank(roles.emergencyPauser);
        containerPrincipal.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(roles.operator);
        cowModule.placeCowOrder(_params());
    }

    /// @dev The mock adapter reverts with OrderUnknown for a digest it never took, so the call
    ///      succeeding is what proves the digest placeCowOrder returned reached the adapter.
    function test_CancelCowOrder() public {
        vm.prank(roles.operator);
        bytes32 orderDigest = cowModule.placeCowOrder(_params());

        _grantCowSwapManager();

        vm.prank(cowSwapManager);
        cowModule.cancelCowOrder(orderDigest);
    }

    function test_ResolveCowOrder() public {
        vm.prank(roles.operator);
        bytes32 orderDigest = cowModule.placeCowOrder(_params());

        _grantCowSwapManager();

        vm.prank(cowSwapManager);
        cowModule.resolveCowOrder(orderDigest);
    }

    function test_RevertIf_CancelCowOrder_CallerNotCowSwapManager() public {
        _expectUnauthorized(roles.operator, "COW_SWAP_MANAGER_ROLE");
        cowModule.cancelCowOrder(bytes32(0));
    }

    function test_RevertIf_ResolveCowOrder_CallerNotCowSwapManager() public {
        _expectUnauthorized(roles.operator, "COW_SWAP_MANAGER_ROLE");
        cowModule.resolveCowOrder(bytes32(0));
    }

    function test_RevertIf_SetCowAdapter_CallerNotTokenManager() public {
        _expectUnauthorized(roles.operator, "TOKEN_MANAGER_ROLE");
        cowModule.setCowAdapter(address(adapter));
    }

    function test_RevertIf_SweepCowAdapter_CallerNotTokenManager() public {
        _expectUnauthorized(roles.operator, "TOKEN_MANAGER_ROLE");
        cowModule.sweepCowAdapter(address(notion));
    }

    function test_RevertIf_SweepCowLane_CallerNotTokenManager() public {
        _expectUnauthorized(roles.operator, "TOKEN_MANAGER_ROLE");
        cowModule.sweepCowLane(0, address(notion));
    }

    // ---- Pending-order call sites (design §5) ----

    function test_RevertIf_SendDepositRequest_OrdersStillPending() public {
        uint256 depositAmount = vault.minDepositBatchSize();
        _deposit(users.alice, depositAmount);

        vm.prank(roles.operator);
        vault.startDepositBatchProcessing();

        (
            ICrossChainContainer.MessageInstruction memory messageInstruction,
            address[] memory bridgeAdapters,
            IBridgeAdapter.BridgeInstruction[] memory bridgeInstructions
        ) = _prepareDepositRequestData(depositAmount);

        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerPrincipal.sendDepositRequest(messageInstruction, bridgeAdapters, bridgeInstructions);
    }

    function test_RevertIf_ReportDeposit_OrdersStillPending() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.BridgeClaimed);
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerPrincipal.reportDeposit();
    }

    function test_RevertIf_ReportWithdrawal_OrdersStillPending() public {
        _setContainerStatus(IContainerPrincipal.ContainerPrincipalStatus.BridgeClaimed);
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerPrincipal.reportWithdrawal();
    }

    // ---- Call sites reached by override (design §5) ----

    function test_RevertIf_BlacklistToken_OrdersStillPending() public {
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.tokenManager);
        containerPrincipal.blacklistToken(address(buyToken));
    }

    function test_BlacklistToken() public {
        vm.prank(roles.tokenManager);
        containerPrincipal.blacklistToken(address(buyToken));

        assertEq(containerPrincipal.isTokenWhitelisted(address(buyToken)), false);
    }

    function test_RevertIf_BlacklistToken_BalanceNotDust() public {
        deal(address(buyToken), address(containerPrincipal), 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.TokenBalanceNotDust.selector, address(buyToken), 1));
        vm.prank(roles.tokenManager);
        containerPrincipal.blacklistToken(address(buyToken));
    }

    /// @dev The check resolves the order first, so the fill it delivers is what the balance check
    ///      then catches; without it the proceeds land one statement before the token leaves the
    ///      whitelist and its router approval is dropped.
    function test_RevertIf_BlacklistToken_FillDeliveredWhileResolving() public {
        adapter.setPendingOrderCount(1);
        deal(address(buyToken), address(adapter), 1e6);
        adapter.setFillOnRequire(address(buyToken), 1e6);

        vm.expectRevert(abi.encodeWithSelector(Errors.TokenBalanceNotDust.selector, address(buyToken), 1e6));
        vm.prank(roles.tokenManager);
        containerPrincipal.blacklistToken(address(buyToken));
    }

    function test_BlacklistToken_BalanceAtDustThreshold() public {
        vm.startPrank(roles.tokenManager);
        containerPrincipal.setWhitelistedTokenDustThreshold(address(buyToken), 10);
        deal(address(buyToken), address(containerPrincipal), 10);
        containerPrincipal.blacklistToken(address(buyToken));
        vm.stopPrank();

        assertEq(containerPrincipal.isTokenWhitelisted(address(buyToken)), false);
    }
}
