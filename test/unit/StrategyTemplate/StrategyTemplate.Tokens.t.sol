// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

contract StrategyTemplateTokensTest is StrategyTemplateBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_SetInputTokens() public {
        uint256 tokenNumber = 5;
        address[] memory inputTokens = _createRandomTokensArray(tokenNumber);

        vm.prank(address(strategyContainer));
        strategy.setInputTokens(inputTokens);

        address[] memory retrievedInputTokens = strategy.getInputTokens();
        assertEq(retrievedInputTokens.length, tokenNumber, "test_SetInputTokens: input tokens length mismatch");
        for (uint256 i = 0; i < tokenNumber; ++i) {
            assertEq(retrievedInputTokens[i], inputTokens[i], "test_SetInputTokens: input token mismatch");
        }
    }

    function test_RevertIf_SetInputTokens_EmptyArray() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategy.setInputTokens(new address[](0));
    }

    function test_RevertIf_SetInputTokens_ZeroAddress() public {
        uint256 tokenNumber = 5;
        address[] memory inputTokens = _createRandomTokensArray(tokenNumber);
        inputTokens[tokenNumber - 1] = address(0);

        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategy.setInputTokens(inputTokens);
    }

    function test_RevertIf_SetInputTokens_DuplicatingAddress() public {
        uint256 tokenNumber = 5;
        address[] memory inputTokens = _createRandomTokensArray(tokenNumber);
        inputTokens[tokenNumber - 1] = inputTokens[tokenNumber - 2];

        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadySet.selector, inputTokens[tokenNumber - 1]));
        strategy.setInputTokens(inputTokens);
    }

    function test_SetOutputTokens() public {
        uint256 tokenNumber = 5;
        address[] memory outputTokens = _createRandomTokensArray(tokenNumber);

        vm.prank(address(strategyContainer));
        strategy.setOutputTokens(outputTokens);

        address[] memory retrievedOutputTokens = strategy.getOutputTokens();
        assertEq(retrievedOutputTokens.length, tokenNumber, "test_SetOutputTokens: output tokens length mismatch");
        for (uint256 i = 0; i < tokenNumber; ++i) {
            assertEq(retrievedOutputTokens[i], outputTokens[i], "test_SetOutputTokens: output token mismatch");
        }
    }

    function test_RevertIf_SetOutputTokens_EmptyArray() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategy.setOutputTokens(new address[](0));
    }

    function test_RevertIf_SetOutputTokens_ZeroAddress() public {
        uint256 tokenNumber = 5;
        address[] memory outputTokens = _createRandomTokensArray(tokenNumber);
        outputTokens[tokenNumber - 1] = address(0);

        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategy.setOutputTokens(outputTokens);
    }

    function test_RevertIf_SetOutputTokens_DuplicatingAddress() public {
        uint256 tokenNumber = 5;
        address[] memory outputTokens = _createRandomTokensArray(tokenNumber);
        outputTokens[tokenNumber - 1] = outputTokens[tokenNumber - 2];

        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadySet.selector, outputTokens[tokenNumber - 1]));
        strategy.setOutputTokens(outputTokens);
    }
}
