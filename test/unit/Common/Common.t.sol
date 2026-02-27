// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {L1Base} from "test/L1Base.t.sol";
import {Common} from "contracts/libraries/helpers/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract WrappedCommon {
    function toUnifiedDecimalsUint8(address token, uint256 amount) external view returns (uint256) {
        return Common.toUnifiedDecimalsUint8(token, amount);
    }

    function fromUnifiedDecimalsUint8(address token, uint256 amount) external view returns (uint256) {
        return Common.fromUnifiedDecimalsUint8(token, amount);
    }
}

contract CommonTest is L1Base {
    WrappedCommon internal common;

    function setUp() public virtual override {
        super.setUp();
        common = new WrappedCommon();
    }

    function testFuzz_ToUnifiedDecimalsUint8(uint8 decimals, uint256 amount) public {
        vm.assume(decimals <= Common.UNIFIED_DECIMALS);
        vm.assume(amount < 1e50);

        MockERC20 token = new MockERC20("Token", "TKN", decimals);
        uint256 unifiedAmount = Common.toUnifiedDecimalsUint8(address(token), amount);
        assertEq(unifiedAmount, amount * 10 ** (Common.UNIFIED_DECIMALS - decimals));
    }

    function test_RevertIf_DecimalsGt18AndToUnifiedDecimalsUint8() public {
        uint8 decimals = Common.UNIFIED_DECIMALS + 1;
        uint256 amount = 10 ** decimals;

        MockERC20 token = new MockERC20("Token", "TKN", decimals);

        vm.expectRevert(abi.encodeWithSelector(Common.DecimalsGt18.selector, decimals));
        common.toUnifiedDecimalsUint8(address(token), amount);
    }

    function test_TheSameDecimalsInToUnifiedDecimalsUint8() public {
        uint256 amount = 10 ** Common.UNIFIED_DECIMALS;

        MockERC20 token = new MockERC20("Token", "TKN", Common.UNIFIED_DECIMALS);
        uint256 unifiedAmount = Common.toUnifiedDecimalsUint8(address(token), amount);
        assertEq(amount, unifiedAmount, "test_ToUnifiedDecimalsUint8: amount mismatch");
    }

    function testFuzz_FromUnifiedDecimalsUint8(uint8 decimals, uint256 unifiedAmount) public {
        vm.assume(decimals <= Common.UNIFIED_DECIMALS);
        vm.assume(unifiedAmount < 1e70);

        MockERC20 token = new MockERC20("Token", "TKN", decimals);
        uint256 amount = Common.fromUnifiedDecimalsUint8(address(token), unifiedAmount);
        assertEq(
            amount,
            unifiedAmount / 10 ** (Common.UNIFIED_DECIMALS - decimals),
            "testFuzz_FromUnifiedDecimalsUint8: amount mismatch"
        );
    }

    function test_RevertIf_DecimalsGt18AndFromUnifiedDecimalsUint8() public {
        uint8 decimals = Common.UNIFIED_DECIMALS + 2;

        MockERC20 token = new MockERC20("Token", "TKN", decimals);

        vm.expectRevert(abi.encodeWithSelector(Common.DecimalsGt18.selector, decimals));
        common.fromUnifiedDecimalsUint8(address(token), 1e18);
    }

    function test_TheSameDecimalsInFromUnifiedDecimalsUint8() public {
        uint8 decimals = Common.UNIFIED_DECIMALS;
        uint256 unifiedAmount = 10 ** decimals;

        MockERC20 token = new MockERC20("Token", "TKN", decimals);
        uint256 amount = Common.fromUnifiedDecimalsUint8(address(token), unifiedAmount);
        assertEq(amount, unifiedAmount, "test_TheSameDecimalsInFromUnifiedDecimalsUint8: amount mismatch");
    }
}
