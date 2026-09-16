// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/CowProtocolAdapter.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {Test} from "forge-std/Test.sol";

import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "test/mocks/MockFeeOnTransferERC20.sol";
import {MockGPv2Settlement} from "test/mocks/MockGPv2Settlement.sol";

/**
 * @dev The module against the real adapter rather than MockCowProtocolAdapter. Two behaviours the
 *      call sites in CLAUDE.local.md §5 rest on cannot be shown against a mock, because a mock
 *      agrees with the adapter by construction rather than by obligation: that
 *      requireNoPendingOrders resolves a filled order in place instead of only reverting, and that
 *      the adapter's pull is exact-or-revert against forceApprove(adapter, sellAmount).
 */
contract CowProtocolModuleAdapterTest is Test {
    MockCowProtocolModule internal module;
    CowProtocolAdapter internal adapter;
    MockGPv2Settlement internal settlement;
    MockERC20 internal sellToken;
    MockERC20 internal buyToken;

    uint256 internal constant SELL_AMOUNT = 1000e18;
    uint256 internal constant BUY_AMOUNT = 990e6;

    function setUp() public {
        module = new MockCowProtocolModule();
        settlement = new MockGPv2Settlement();
        adapter = new CowProtocolAdapter(address(module), address(settlement));

        sellToken = new MockERC20("Sell", "SELL", 18);
        buyToken = new MockERC20("Buy", "BUY", 6);

        module.setCowAdapter(address(adapter));
        module.whitelistToken(address(sellToken));
        module.whitelistToken(address(buyToken));

        sellToken.mint(address(module), SELL_AMOUNT);
        buyToken.mint(address(settlement), BUY_AMOUNT);
    }

    function _params(
        address sellToken_,
        uint256 sellAmount
    ) internal view returns (ICowProtocolAdapter.OrderParams memory) {
        return
            ICowProtocolAdapter.OrderParams({
                sellToken: sellToken_,
                buyToken: address(buyToken),
                sellAmount: sellAmount,
                buyAmount: BUY_AMOUNT,
                validTo: uint32(block.timestamp + 1 hours),
                appData: bytes32(0)
            });
    }

    /// @dev Settles the order the way a solver would, leaving the adapter's record untouched.
    function _fill(bytes32 orderDigest) internal returns (address lane) {
        lane = adapter.laneAt(adapter.orderRecord(orderDigest).lane);

        settlement.settle(
            adapter.orderUidOf(orderDigest),
            lane,
            address(sellToken),
            SELL_AMOUNT,
            address(buyToken),
            BUY_AMOUNT,
            address(module)
        );
    }

    function test_RequireNoPendingOrders_ResolvesFilledOrderInPlace() public {
        bytes32 orderDigest = module.placeCowOrder(_params(address(sellToken), SELL_AMOUNT));
        address lane = _fill(orderDigest);

        assertEq(module.pendingCowOrderCount(), 1, "fill alone does not clear the order");

        module.requireNoPendingOrders();

        assertEq(module.pendingCowOrderCount(), 0, "order not resolved in place");
        assertEq(
            uint8(adapter.orderRecord(orderDigest).status),
            uint8(ICowProtocolAdapter.OrderStatus.Filled),
            "order not recorded as filled"
        );
        assertEq(IERC20(sellToken).allowance(lane, address(settlement)), 0, "lane allowance not dropped");
        assertEq(buyToken.balanceOf(address(module)), BUY_AMOUNT, "proceeds did not reach the module");
    }

    /// @dev The counterpart Vault relies on: the view reports a filled order as still pending, so
    ///      it blocks rather than resolving on the Vault's behalf.
    function test_PendingCowOrderCount_ReportsFilledOrderAsPending() public {
        bytes32 orderDigest = module.placeCowOrder(_params(address(sellToken), SELL_AMOUNT));
        _fill(orderDigest);

        assertEq(module.pendingCowOrderCount(), 1, "view resolved an order it should only report");
        assertEq(
            uint8(adapter.orderRecord(orderDigest).status),
            uint8(ICowProtocolAdapter.OrderStatus.Pending),
            "view moved the order out of Pending"
        );
    }

    function test_RevertIf_RequireNoPendingOrders_OrderUnfilled() public {
        module.placeCowOrder(_params(address(sellToken), SELL_AMOUNT));

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrdersStillPending.selector, 1));
        module.requireNoPendingOrders();
    }

    function test_PlaceCowOrder_PullsExactlySellAmount() public {
        bytes32 orderDigest = module.placeCowOrder(_params(address(sellToken), SELL_AMOUNT));
        address lane = adapter.laneAt(adapter.orderRecord(orderDigest).lane);

        assertEq(sellToken.balanceOf(address(module)), 0, "module kept or overpaid sell tokens");
        assertEq(sellToken.balanceOf(lane), SELL_AMOUNT, "lane did not receive the whole sell amount");
        assertEq(sellToken.allowance(address(module), address(adapter)), 0, "approval left a residual");
        assertEq(sellToken.allowance(lane, address(settlement)), SELL_AMOUNT, "lane did not approve the relayer");
    }

    function test_RevertIf_PlaceCowOrder_SellTokenDeliversShortfall() public {
        MockFeeOnTransferERC20 feeToken = new MockFeeOnTransferERC20("Fee", "FEE");
        feeToken.mint(address(module), SELL_AMOUNT);
        module.whitelistToken(address(feeToken));

        uint256 delivered = SELL_AMOUNT - (SELL_AMOUNT * feeToken.FEE_BPS()) / 10_000;

        vm.expectRevert(
            abi.encodeWithSelector(ICowProtocolAdapter.SellTokenShortfall.selector, SELL_AMOUNT, delivered)
        );
        module.placeCowOrder(_params(address(feeToken), SELL_AMOUNT));
    }
}
