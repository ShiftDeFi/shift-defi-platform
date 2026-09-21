// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";

import {Errors} from "contracts/libraries/Errors.sol";

import {ContainerLocalBaseTest} from "test/unit/ContainerLocal/ContainerLocalBase.t.sol";
import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract ContainerLocalCowProtocolTest is ContainerLocalBaseTest {
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

        cowModule = ICowProtocolModule(address(containerLocal));
        adapter = new MockCowProtocolAdapter(address(cowModule));
        buyToken = new MockERC20("Buy", "BUY", 6);

        vm.prank(roles.tokenManager);
        cowModule.setCowAdapter(address(adapter));

        _whitelistToken(address(containerLocal), address(buyToken));
        deal(address(notion), address(containerLocal), SELL_AMOUNT);
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
        IAccessControl(address(containerLocal)).grantRole(COW_SWAP_MANAGER_ROLE, cowSwapManager);
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
        assertEq(cowModule.pendingCowOrderCount(), 0);
    }

    function test_RevertIf_PlaceCowOrder_CallerNotOperator() public {
        _expectUnauthorized(roles.tokenManager, "OPERATOR_ROLE");
        cowModule.placeCowOrder(_params());
    }

    function test_RevertIf_PlaceCowOrder_Paused() public {
        vm.prank(roles.emergencyPauser);
        containerLocal.pause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(roles.operator);
        cowModule.placeCowOrder(_params());
    }

    function test_RevertIf_PlaceCowOrder_ResolvingEmergency() public {
        vm.prank(address(strategy));
        containerLocal.startEmergencyResolution();

        vm.expectRevert(abi.encodeWithSignature("EmergencyResolutionInProgress()"));
        vm.prank(roles.operator);
        cowModule.placeCowOrder(_params());
    }

    function test_RevertIf_PlaceCowOrder_InReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        vm.expectRevert(Errors.ReshufflingModeEnabled.selector);
        vm.prank(roles.operator);
        cowModule.placeCowOrder(_params());
    }

    function test_PlaceCowOrderInReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = containerLocal.placeCowOrderInReshufflingMode(_params());

        assertEq(orderDigest, keccak256(abi.encode(_params())));
    }

    function test_RevertIf_PlaceCowOrderInReshufflingMode_NotInReshufflingMode() public {
        vm.expectRevert(Errors.ReshufflingModeDisabled.selector);
        vm.prank(roles.reshufflingExecutor);
        containerLocal.placeCowOrderInReshufflingMode(_params());
    }

    /// @dev onlyInReshufflingMode runs before onlyRole, so the mode has to be open for the role
    ///      check to be what rejects the caller.
    function test_RevertIf_PlaceCowOrderInReshufflingMode_CallerNotReshufflingExecutor() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        _expectUnauthorized(roles.operator, "RESHUFFLING_EXECUTOR_ROLE");
        containerLocal.placeCowOrderInReshufflingMode(_params());
    }

    /// @dev The container is not Pausable-gated in the mode: placeCowOrder carries whenNotPaused
    ///      and this does not, matching enterInReshufflingMode and exitInReshufflingMode.
    function test_PlaceCowOrderInReshufflingMode_WhilePaused() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        vm.prank(roles.emergencyPauser);
        containerLocal.pause();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = containerLocal.placeCowOrderInReshufflingMode(_params());

        assertEq(orderDigest, keccak256(abi.encode(_params())));
    }

    /// @dev Same asymmetry for notResolvingEmergency. The mode has to be opened first, because
    ///      enableReshufflingMode itself carries notResolvingEmergency.
    function test_PlaceCowOrderInReshufflingMode_WhileResolvingEmergency() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        vm.prank(address(strategy));
        containerLocal.startEmergencyResolution();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = containerLocal.placeCowOrderInReshufflingMode(_params());

        assertEq(orderDigest, keccak256(abi.encode(_params())));
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

    /// @dev An order placed by the reshuffling executor inside the mode is cancelled by the cow
    ///      swap manager outside it: cancel and resolve carry no mode modifier.
    function test_CancelCowOrder_PlacedInReshufflingMode() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        vm.prank(roles.reshufflingExecutor);
        bytes32 orderDigest = containerLocal.placeCowOrderInReshufflingMode(_params());

        vm.prank(roles.reshufflingExecutor);
        containerLocal.disableReshufflingMode();

        _grantCowSwapManager();

        vm.prank(cowSwapManager);
        cowModule.cancelCowOrder(orderDigest);
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

    function test_RevertIf_ReportDeposit_OrdersStillPending() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.AllStrategiesEntered);
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerLocal.reportDeposit();
    }

    function test_RevertIf_ReportWithdrawal_OrdersStillPending() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.AllStrategiesExited);
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerLocal.reportWithdrawal();
    }

    function test_RevertIf_EnterStrategy_OrdersStillPending() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerLocal.enterStrategy(address(strategy), new uint256[](1), 0);
    }

    function test_RevertIf_EnterStrategyMultiple_OrdersStillPending() public {
        _setContainerStatus(IContainerLocal.ContainerLocalStatus.DepositRequestRegistered);
        adapter.setPendingOrderCount(1);

        address[] memory strategies = new address[](1);
        strategies[0] = address(strategy);
        uint256[][] memory inputAmounts = new uint256[][](1);
        inputAmounts[0] = new uint256[](1);
        uint256[] memory minNavDelta = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.operator);
        containerLocal.enterStrategyMultiple(strategies, inputAmounts, minNavDelta);
    }

    // ---- Call sites reached by override (design §5) ----

    function test_RevertIf_EnableReshufflingMode_OrdersStillPending() public {
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();
    }

    function test_RevertIf_DisableReshufflingMode_OrdersStillPending() public {
        vm.prank(roles.reshufflingManager);
        containerLocal.enableReshufflingMode();

        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.reshufflingExecutor);
        containerLocal.disableReshufflingMode();
    }

    function test_RevertIf_BlacklistToken_OrdersStillPending() public {
        adapter.setPendingOrderCount(1);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        vm.prank(roles.tokenManager);
        containerLocal.blacklistToken(address(buyToken));
    }

    function test_BlacklistToken() public {
        vm.prank(roles.tokenManager);
        containerLocal.blacklistToken(address(buyToken));

        assertEq(containerLocal.isTokenWhitelisted(address(buyToken)), false);
    }

    function test_RevertIf_BlacklistToken_BalanceNotDust() public {
        deal(address(buyToken), address(containerLocal), 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.TokenBalanceNotDust.selector, address(buyToken), 1));
        vm.prank(roles.tokenManager);
        containerLocal.blacklistToken(address(buyToken));
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
        containerLocal.blacklistToken(address(buyToken));
    }

    function test_BlacklistToken_BalanceAtDustThreshold() public {
        vm.startPrank(roles.tokenManager);
        containerLocal.setWhitelistedTokenDustThreshold(address(buyToken), 10);
        deal(address(buyToken), address(containerLocal), 10);
        containerLocal.blacklistToken(address(buyToken));
        vm.stopPrank();

        assertEq(containerLocal.isTokenWhitelisted(address(buyToken)), false);
    }
}
