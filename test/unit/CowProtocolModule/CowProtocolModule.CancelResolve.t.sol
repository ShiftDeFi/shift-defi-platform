// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {Test} from "forge-std/Test.sol";

import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";

import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract CowProtocolModuleCancelResolveTest is Test {
    MockCowProtocolModule internal module;
    MockCowProtocolAdapter internal adapter;
    MockERC20 internal sellToken;
    MockERC20 internal buyToken;

    bytes32 internal orderDigest;

    uint256 internal constant SELL_AMOUNT = 1000e18;

    function setUp() public {
        module = new MockCowProtocolModule();
        adapter = new MockCowProtocolAdapter(address(module));
        sellToken = new MockERC20("Sell", "SELL", 18);
        buyToken = new MockERC20("Buy", "BUY", 6);

        module.setCowAdapter(address(adapter));
        module.whitelistToken(address(sellToken));
        module.whitelistToken(address(buyToken));
        sellToken.mint(address(module), SELL_AMOUNT);

        orderDigest = module.placeCowOrder(
            ICowProtocolAdapter.OrderParams({
                sellToken: address(sellToken),
                buyToken: address(buyToken),
                sellAmount: SELL_AMOUNT,
                buyAmount: 1,
                validTo: uint32(block.timestamp + 1 hours),
                appData: bytes32(0)
            })
        );
    }

    function test_CancelCowOrder() public {
        vm.expectCall(address(adapter), abi.encodeCall(ICowProtocolAdapter.cancelOrder, (orderDigest)));
        module.cancelCowOrder(orderDigest);
    }

    function test_ResolveCowOrder() public {
        vm.expectCall(address(adapter), abi.encodeCall(ICowProtocolAdapter.resolveOrder, (orderDigest)));
        module.resolveCowOrder(orderDigest);
    }

    function test_RevertIf_CancelCowOrder_AdapterNotSet() public {
        MockCowProtocolModule bare = new MockCowProtocolModule();

        vm.expectRevert(ICowProtocolModule.CowAdapterNotSet.selector);
        bare.cancelCowOrder(orderDigest);
    }

    function test_RevertIf_ResolveCowOrder_AdapterNotSet() public {
        MockCowProtocolModule bare = new MockCowProtocolModule();

        vm.expectRevert(ICowProtocolModule.CowAdapterNotSet.selector);
        bare.resolveCowOrder(orderDigest);
    }

    function test_RevertIf_CancelCowOrder_OrderUnknown() public {
        bytes32 unknownDigest = keccak256("unknown");

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrderUnknown.selector, unknownDigest));
        module.cancelCowOrder(unknownDigest);
    }

    function test_RevertIf_ResolveCowOrder_OrderUnknown() public {
        bytes32 unknownDigest = keccak256("unknown");

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolAdapter.OrderUnknown.selector, unknownDigest));
        module.resolveCowOrder(unknownDigest);
    }
}
