// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {StrategyTemplateBaseTest} from "./StrategyTemplateBase.t.sol";

import {Errors} from "contracts/libraries/Errors.sol";

contract StrategyTemplateTokensTest is StrategyTemplateBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_SetInputTokens() public {
        uint256 tokenNumber = 5;
        address[] memory inputTokens = _createRandomTokensArray(tokenNumber);

        _whitelistTokensIfNeeded(address(strategyContainer), inputTokens);

        vm.prank(address(strategyContainer));
        strategy.setInputTokens(inputTokens);

        address[] memory retrievedInputTokens = strategy.getInputTokens();
        assertEq(retrievedInputTokens.length, tokenNumber, "test_SetInputTokens: input tokens length mismatch");
        for (uint256 i = 0; i < tokenNumber; ++i) {
            assertEq(retrievedInputTokens[i], inputTokens[i], "test_SetInputTokens: input token mismatch");
        }
    }

    function test_SetStrategyInputTokens_OverwritingExistingTokens() public {
        uint256 initialTokenNumber = 2;
        address[] memory initialInputTokens = _createRandomTokensArray(initialTokenNumber);

        _whitelistTokensIfNeeded(address(strategyContainer), initialInputTokens);

        vm.prank(address(strategyContainer));
        strategy.setInputTokens(initialInputTokens);

        address[] memory retrievedInputTokens = strategy.getInputTokens();
        assertEq(
            retrievedInputTokens.length,
            initialTokenNumber,
            "test_SetStrategyInputTokens_OverwritingExistingTokens: initial token number mismatch"
        );

        for (uint256 i = 0; i < initialTokenNumber; ++i) {
            assertEq(
                retrievedInputTokens[i],
                initialInputTokens[i],
                "test_SetStrategyInputTokens_OverwritingExistingTokens: initial input token mismatch"
            );
        }

        uint256 newTokenNumber = 4;
        address[] memory newInputTokens = _createRandomTokensArray(newTokenNumber);

        _whitelistTokensIfNeeded(address(strategyContainer), newInputTokens);

        vm.prank(address(strategyContainer));
        strategy.setInputTokens(newInputTokens);

        retrievedInputTokens = strategy.getInputTokens();
        assertEq(
            retrievedInputTokens.length,
            newTokenNumber,
            "test_SetStrategyInputTokens_OverwritingExistingTokens: new token number mismatch"
        );
        for (uint256 i = 0; i < newTokenNumber; ++i) {
            assertEq(
                retrievedInputTokens[i],
                newInputTokens[i],
                "test_SetStrategyInputTokens_OverwritingExistingTokens: new input token mismatch"
            );
        }
    }

    function test_RevertIf_SetInputTokens_EmptyArray() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategy.setInputTokens(new address[](0));
    }

    function test_RevertIf_SetInputTokens_DuplicatingAddress() public {
        uint256 tokenNumber = 5;
        address[] memory inputTokens = _createRandomTokensArray(tokenNumber);
        inputTokens[tokenNumber - 1] = inputTokens[tokenNumber - 2];

        _whitelistTokensIfNeeded(address(strategyContainer), inputTokens);

        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadySet.selector, inputTokens[tokenNumber - 1]));
        strategy.setInputTokens(inputTokens);
    }

    function test_SetOutputTokens() public {
        uint256 tokenNumber = 5;
        address[] memory outputTokens = _createRandomTokensArray(tokenNumber);

        _whitelistTokensIfNeeded(address(strategyContainer), outputTokens);

        vm.prank(address(strategyContainer));
        strategy.setOutputTokens(outputTokens);

        address[] memory retrievedOutputTokens = strategy.getOutputTokens();
        assertEq(retrievedOutputTokens.length, tokenNumber, "test_SetOutputTokens: output tokens length mismatch");
        for (uint256 i = 0; i < tokenNumber; ++i) {
            assertEq(retrievedOutputTokens[i], outputTokens[i], "test_SetOutputTokens: output token mismatch");
        }
    }

    function test_SetStrategyOutputTokens_OverwritingExistingTokens() public {
        uint256 initialTokenNumber = 2;
        address[] memory initialOutputTokens = _createRandomTokensArray(initialTokenNumber);

        _whitelistTokensIfNeeded(address(strategyContainer), initialOutputTokens);

        vm.prank(address(strategyContainer));
        strategy.setOutputTokens(initialOutputTokens);

        address[] memory retrievedOutputTokens = strategy.getOutputTokens();
        assertEq(
            retrievedOutputTokens.length,
            initialTokenNumber,
            "test_SetStrategyOutputTokens_OverwritingExistingTokens: initial token number mismatch"
        );

        for (uint256 i = 0; i < initialTokenNumber; ++i) {
            assertEq(
                retrievedOutputTokens[i],
                initialOutputTokens[i],
                "test_SetStrategyOutputTokens_OverwritingExistingTokens: initial output token mismatch"
            );
        }

        uint256 newTokenNumber = 4;
        address[] memory newOutputTokens = _createRandomTokensArray(newTokenNumber);

        _whitelistTokensIfNeeded(address(strategyContainer), newOutputTokens);

        vm.prank(address(strategyContainer));
        strategy.setOutputTokens(newOutputTokens);

        retrievedOutputTokens = strategy.getOutputTokens();
        assertEq(
            retrievedOutputTokens.length,
            newTokenNumber,
            "test_SetStrategyOutputTokens_OverwritingExistingTokens: new token number mismatch"
        );
        for (uint256 i = 0; i < newTokenNumber; ++i) {
            assertEq(
                retrievedOutputTokens[i],
                newOutputTokens[i],
                "test_SetStrategyOutputTokens_OverwritingExistingTokens: new output token mismatch"
            );
        }
    }

    function test_RevertIf_SetOutputTokens_EmptyArray() public {
        vm.prank(address(strategyContainer));
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategy.setOutputTokens(new address[](0));
    }

    function test_RevertIf_SetOutputTokens_DuplicatingAddress() public {
        uint256 tokenNumber = 5;
        address[] memory outputTokens = _createRandomTokensArray(tokenNumber);
        outputTokens[tokenNumber - 1] = outputTokens[tokenNumber - 2];

        _whitelistTokensIfNeeded(address(strategyContainer), outputTokens);

        vm.prank(address(strategyContainer));
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadySet.selector, outputTokens[tokenNumber - 1]));
        strategy.setOutputTokens(outputTokens);
    }
}
