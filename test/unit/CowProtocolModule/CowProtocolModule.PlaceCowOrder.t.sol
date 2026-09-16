// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {Test} from "forge-std/Test.sol";

import {ICowProtocolModule} from "contracts/interfaces/ICowProtocolModule.sol";

import {MockCowProtocolAdapter} from "test/mocks/MockCowProtocolAdapter.sol";
import {MockCowProtocolModule} from "test/mocks/MockCowProtocolModule.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract CowProtocolModulePlaceCowOrderTest is Test {
    MockCowProtocolModule internal module;
    MockCowProtocolAdapter internal adapter;
    MockERC20 internal sellToken;
    MockERC20 internal buyToken;

    uint256 internal constant SELL_AMOUNT = 1000e18;
    uint256 internal constant BUY_AMOUNT = 990e6;

    function setUp() public {
        module = new MockCowProtocolModule();
        adapter = new MockCowProtocolAdapter(address(module));
        sellToken = new MockERC20("Sell", "SELL", 18);
        buyToken = new MockERC20("Buy", "BUY", 6);

        module.setCowAdapter(address(adapter));
        module.whitelistToken(address(sellToken));
        module.whitelistToken(address(buyToken));
        sellToken.mint(address(module), SELL_AMOUNT);
    }

    function _params() internal view returns (ICowProtocolAdapter.OrderParams memory) {
        return
            ICowProtocolAdapter.OrderParams({
                sellToken: address(sellToken),
                buyToken: address(buyToken),
                sellAmount: SELL_AMOUNT,
                buyAmount: BUY_AMOUNT,
                validTo: uint32(block.timestamp + 1 hours),
                appData: bytes32(0)
            });
    }

    function test_PlaceCowOrder() public {
        ICowProtocolAdapter.OrderParams memory params = _params();

        vm.expectEmit(true, true, true, true, address(module));
        emit ICowProtocolModule.CowOrderPlaced(
            keccak256(abi.encode(params)),
            address(sellToken),
            address(buyToken),
            SELL_AMOUNT,
            BUY_AMOUNT,
            params.validTo
        );

        bytes32 orderDigest = module.placeCowOrder(params);

        assertEq(orderDigest, keccak256(abi.encode(params)));
        assertEq(sellToken.balanceOf(address(adapter)), SELL_AMOUNT);
        assertEq(sellToken.balanceOf(address(module)), 0);
        assertEq(sellToken.allowance(address(module), address(adapter)), 0);
    }

    function test_RevertIf_PlaceCowOrder_AdapterNotSet() public {
        MockCowProtocolModule bare = new MockCowProtocolModule();
        bare.whitelistToken(address(sellToken));
        bare.whitelistToken(address(buyToken));

        vm.expectRevert(ICowProtocolModule.CowAdapterNotSet.selector);
        bare.placeCowOrder(_params());
    }

    function test_RevertIf_PlaceCowOrder_SellTokenNotWhitelisted() public {
        MockERC20 other = new MockERC20("Other", "OTHER", 18);
        ICowProtocolAdapter.OrderParams memory params = _params();
        params.sellToken = address(other);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolModule.OrderTokenNotWhitelisted.selector, address(other)));
        module.placeCowOrder(params);
    }

    function test_RevertIf_PlaceCowOrder_BuyTokenNotWhitelisted() public {
        MockERC20 other = new MockERC20("Other", "OTHER", 18);
        ICowProtocolAdapter.OrderParams memory params = _params();
        params.buyToken = address(other);

        vm.expectRevert(abi.encodeWithSelector(ICowProtocolModule.OrderTokenNotWhitelisted.selector, address(other)));
        module.placeCowOrder(params);
    }
}
