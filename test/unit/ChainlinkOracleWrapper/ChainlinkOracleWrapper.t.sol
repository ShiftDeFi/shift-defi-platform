// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ChainlinkOracleWrapper} from "contracts/priceOracles/ChainlinkOracleWrapper.sol";
import {IChainlinkOracleWrapper} from "contracts/interfaces/IChainlinkOracleWrapper.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";

import {MockChainlinkPriceFeed} from "test/mocks/MockChainlinkPriceFeed.sol";

import {L1Base} from "test/L1Base.t.sol";

contract ChainlinkOracleWrapperTest is L1Base {
    ChainlinkOracleWrapper internal chainlinkOracleWrapper;
    address internal chainlinkFeed;
    uint256 internal referencePrice;
    uint8 internal referenceDecimals;

    function setUp() public override {
        super.setUp();

        referencePrice = 1e18;
        referenceDecimals = 18;
        chainlinkFeed = address(new MockChainlinkPriceFeed(int256(referencePrice), referenceDecimals));
        chainlinkOracleWrapper = new ChainlinkOracleWrapper(roles.defaultAdmin, roles.oracleManager);
    }

    function test_SetChainlinkFeed() public {
        vm.expectEmit();
        emit IChainlinkOracleWrapper.ChainlinkFeedSet(address(notion), address(chainlinkFeed));

        vm.prank(roles.oracleManager);
        chainlinkOracleWrapper.setChainlinkFeed(address(notion), address(chainlinkFeed));
        assertEq(
            chainlinkOracleWrapper.tokenToChainlinkFeed(address(notion)),
            address(chainlinkFeed),
            "test_setChainlinkFeed: must set chainlink feed"
        );

        address newChainlinkFeed = address(new MockChainlinkPriceFeed(int256(referencePrice), referenceDecimals));
        vm.prank(roles.oracleManager);
        chainlinkOracleWrapper.setChainlinkFeed(address(notion), newChainlinkFeed);
        assertEq(
            chainlinkOracleWrapper.tokenToChainlinkFeed(address(notion)),
            newChainlinkFeed,
            "test_setChainlinkFeed: must set chainlink feed"
        );
    }

    function test_RevertIf_ZeroAddressAndSetChainlinkFeed() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.oracleManager);
        chainlinkOracleWrapper.setChainlinkFeed(address(0), address(123));

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(roles.oracleManager);
        chainlinkOracleWrapper.setChainlinkFeed(address(123), address(0));
    }

    function test_GetPrice() public {
        vm.prank(roles.oracleManager);
        chainlinkOracleWrapper.setChainlinkFeed(address(notion), address(chainlinkFeed));

        (uint256 actualPrice, uint8 actualDecimals) = chainlinkOracleWrapper.getPrice(address(notion));
        assertEq(actualPrice, referencePrice, "test_getPrice: must return price");
        assertEq(actualDecimals, referenceDecimals, "test_getPrice: must return decimals");
    }

    function test_RevertIf_ZeroAddressAndGetPrice() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        chainlinkOracleWrapper.getPrice(address(0));
    }

    function test_RevertIf_ChainlinkFeedNotFoundAndGetPrice() public {
        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkOracleWrapper.ChainlinkFeedNotFound.selector, address(notion))
        );
        chainlinkOracleWrapper.getPrice(address(notion));
    }

    function test_RevertIf_ZeroPriceAndGetPrice() public {
        vm.prank(roles.oracleManager);
        chainlinkOracleWrapper.setChainlinkFeed(address(notion), address(chainlinkFeed));

        MockChainlinkPriceFeed(chainlinkFeed).setAnswer(0);

        vm.expectRevert(abi.encodeWithSelector(IChainlinkOracleWrapper.ZeroPrice.selector, address(notion)));
        chainlinkOracleWrapper.getPrice(address(notion));
    }

    function test_RevertIf_NotImplementedAndDecimals() public {
        vm.expectRevert(Errors.NotImplemented.selector);
        chainlinkOracleWrapper.decimals();
    }
}
