// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {Errors} from "contracts/libraries/helpers/Errors.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";

contract StrategyContainerSettersTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal strategy;
    address internal whitelistedToken;

    function setUp() public override {
        super.setUp();

        whitelistedToken = address(_deployMockERC20("Token", "TKN", 18));
        strategy = new MockStrategyInterfaceBased();
        vm.prank(roles.tokenManager);
        strategyContainer.whitelistToken(whitelistedToken);
    }

    // ---- setReshufflingGateway tests ----

    function test_SetReshufflingGateway() public {
        address reshufflingGateway = makeAddr("RESHUFFLING_GATEWAY");
        vm.prank(roles.reshufflingManager);
        strategyContainer.setReshufflingGateway(reshufflingGateway);
        assertEq(
            strategyContainer.reshufflingGateway(),
            reshufflingGateway,
            "test_SetReshufflingGateway: Reshuffling gateway not set"
        );
    }

    function test_RevertIf_SetReshufflingGateway_ZeroAddress() public {
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.setReshufflingGateway(address(0));
    }

    function test_RevertIf_SetReshufflingGateway_NotReshufflingManager() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                RESHUFFLING_MANAGER_ROLE
            )
        );
        strategyContainer.setReshufflingGateway(makeAddr("RESHUFFLING_GATEWAY"));
    }

    // ---- setFeePct tests ----

    function test_SetFeePct() public {
        uint256 feePct = 100;
        vm.prank(roles.strategyManager);
        strategyContainer.setFeePct(feePct);
        assertEq(strategyContainer.feePct(), feePct, "test_SetFeePct: Fee percentage not set");
    }

    function test_RevertIf_SetFeePct_ExceedsBPS() public {
        vm.prank(roles.strategyManager);
        vm.expectRevert(Errors.IncorrectAmount.selector);
        strategyContainer.setFeePct(MAX_BPS + 1);
    }

    function test_RevertIf_SetFeePct_NotStrategyManager() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                STRATEGY_MANAGER_ROLE
            )
        );
        strategyContainer.setFeePct(100);
    }

    // ---- setPriceOracle tests ----

    function test_SetPriceOracle() public {
        address priceOracle = makeAddr("PRICE_ORACLE");
        vm.prank(roles.strategyManager);
        strategyContainer.setPriceOracle(priceOracle);
        assertEq(strategyContainer.priceOracle(), priceOracle, "test_SetPriceOracle: Price oracle not set");
    }

    function test_RevertIf_SetPriceOracle_ZeroAddress() public {
        vm.prank(roles.strategyManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.setPriceOracle(address(0));
    }

    function test_RevertIf_SetPriceOracle_NotStrategyManager() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                STRATEGY_MANAGER_ROLE
            )
        );
        strategyContainer.setPriceOracle(makeAddr("PRICE_ORACLE"));
    }

    // ---- setTreasury tests ----

    function test_SetTreasury() public {
        address _treasury = makeAddr("TREASURY");
        vm.prank(roles.strategyManager);
        strategyContainer.setTreasury(_treasury);
        assertEq(strategyContainer.treasury(), _treasury, "test_SetTreasury: Treasury not set");
    }

    function test_RevertIf_SetTreasury_ZeroAddress() public {
        vm.prank(roles.strategyManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.setTreasury(address(0));
    }

    function test_RevertIf_SetTreasury_NotStrategyManager() public {
        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                STRATEGY_MANAGER_ROLE
            )
        );
        strategyContainer.setTreasury(makeAddr("TREASURY"));
    }

    // ---- setStrategyInputTokens tests ----

    function test_SetStrategyInputTokens_EmptyContainer_StrategyNotFound() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, _createTokensArray(address(notion)));

        address[] memory newInputTokens = _createTokensArray(whitelistedToken);

        vm.startPrank(roles.strategyManager);
        vm.expectCall(
            address(strategy),
            abi.encodeWithSelector(IStrategyTemplate.setInputTokens.selector, newInputTokens)
        );
        strategyContainer.setStrategyInputTokens(address(strategy), newInputTokens);
        vm.stopPrank();

        address[] memory retrievedInputTokens = IStrategyTemplate(address(strategy)).getInputTokens();
        assertEq(
            retrievedInputTokens.length,
            1,
            "test_SetStrategyInputTokens_EmptyContainer: Input tokens length should be 1"
        );
        assertEq(
            retrievedInputTokens[0],
            whitelistedToken,
            "test_SetStrategyInputTokens_EmptyContainer: Input token should match"
        );
    }

    function test_SetStrategyInputTokens_ExistingStrategy() public {
        address[] memory initialInputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), initialInputTokens, _createTokensArray(address(notion)));

        address[] memory newInputTokens = new address[](2);
        newInputTokens[0] = address(notion);
        newInputTokens[1] = address(notion);

        vm.startPrank(roles.strategyManager);
        vm.expectCall(
            address(strategy),
            abi.encodeWithSelector(IStrategyTemplate.setInputTokens.selector, newInputTokens)
        );
        strategyContainer.setStrategyInputTokens(address(strategy), newInputTokens);
        vm.stopPrank();

        address[] memory retrievedInputTokens = IStrategyTemplate(address(strategy)).getInputTokens();
        assertEq(
            retrievedInputTokens.length,
            2,
            "test_SetStrategyInputTokens_ExistingStrategy: Input tokens length should be 2"
        );
        assertEq(
            retrievedInputTokens[0],
            address(notion),
            "test_SetStrategyInputTokens_ExistingStrategy: First token should match"
        );
        assertEq(
            retrievedInputTokens[1],
            address(notion),
            "test_SetStrategyInputTokens_ExistingStrategy: Second token should match"
        );
    }

    function test_RevertIf_StrategyNotFoundInSetStrategyInputTokens() public {
        address nonStrategy = makeAddr("NON_STRATEGY");
        address[] memory inputTokens = _createTokensArray(address(notion));

        vm.startPrank(roles.strategyManager);
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.setStrategyInputTokens(nonStrategy, inputTokens);
        vm.stopPrank();
    }

    function test_RevertIf_NotStrategyManagerInSetStrategyInputTokens() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, _createTokensArray(address(notion)));

        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                STRATEGY_MANAGER_ROLE
            )
        );
        strategyContainer.setStrategyInputTokens(address(strategy), inputTokens);
    }

    function test_RevertIf_InputTokensIsEmpty() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, _createTokensArray(address(notion)));

        vm.startPrank(roles.strategyManager);
        address[] memory emptyInputTokens = new address[](0);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategyContainer.setStrategyInputTokens(address(strategy), emptyInputTokens);
        vm.stopPrank();
    }

    function test_RevertIf_InputTokenIsZeroAddress() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, _createTokensArray(address(notion)));

        vm.startPrank(roles.strategyManager);
        address[] memory tokensWithZero = _createTokensArray(address(0));
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.setStrategyInputTokens(address(strategy), tokensWithZero);
        vm.stopPrank();
    }

    function test_RevertIf_InputTokenNotWhitelisted() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, _createTokensArray(address(notion)));

        vm.startPrank(roles.strategyManager);
        address nonWhitelistedToken = address(_deployMockERC20("Token", "TKN", 18));
        address[] memory tokensWithNonWhitelisted = _createTokensArray(nonWhitelistedToken);
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, nonWhitelistedToken));
        strategyContainer.setStrategyInputTokens(address(strategy), tokensWithNonWhitelisted);
        vm.stopPrank();
    }

    // ---- setStrategyOutputTokens tests ----

    function test_SetStrategyOutputTokens_EmptyContainer() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        address[] memory outputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, outputTokens);

        address[] memory newOutputTokens = _createTokensArray(whitelistedToken);

        vm.startPrank(roles.strategyManager);
        vm.expectCall(
            address(strategy),
            abi.encodeWithSelector(IStrategyTemplate.setOutputTokens.selector, newOutputTokens)
        );
        strategyContainer.setStrategyOutputTokens(address(strategy), newOutputTokens);
        vm.stopPrank();

        address[] memory retrievedOutputTokens = IStrategyTemplate(address(strategy)).getOutputTokens();
        assertEq(
            retrievedOutputTokens.length,
            1,
            "test_SetStrategyOutputTokens_EmptyContainer: Output tokens length should be 1"
        );
        assertEq(
            retrievedOutputTokens[0],
            whitelistedToken,
            "test_SetStrategyOutputTokens_EmptyContainer: Output token should match"
        );
    }

    function test_SetStrategyOutputTokens_ExistingStrategy() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        address[] memory initialOutputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, initialOutputTokens);

        address[] memory newOutputTokens = new address[](2);
        newOutputTokens[0] = address(notion);
        newOutputTokens[1] = address(notion);

        vm.startPrank(roles.strategyManager);
        vm.expectCall(
            address(strategy),
            abi.encodeWithSelector(IStrategyTemplate.setOutputTokens.selector, newOutputTokens)
        );
        strategyContainer.setStrategyOutputTokens(address(strategy), newOutputTokens);
        vm.stopPrank();

        address[] memory retrievedOutputTokens = IStrategyTemplate(address(strategy)).getOutputTokens();
        assertEq(
            retrievedOutputTokens.length,
            2,
            "test_SetStrategyOutputTokens_ExistingStrategy: Output tokens length should be 2"
        );
        assertEq(
            retrievedOutputTokens[0],
            address(notion),
            "test_SetStrategyOutputTokens_ExistingStrategy: First token should match"
        );
        assertEq(
            retrievedOutputTokens[1],
            address(notion),
            "test_SetStrategyOutputTokens_ExistingStrategy: Second token should match"
        );
    }

    function test_RevertIf_StrategyNotFoundInSetStrategyOutputTokens() public {
        address nonStrategy = makeAddr("NON_STRATEGY");
        address[] memory outputTokens = _createTokensArray(address(notion));

        vm.startPrank(roles.strategyManager);
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.setStrategyOutputTokens(nonStrategy, outputTokens);
        vm.stopPrank();
    }

    function test_RevertIf_NotStrategyManagerInSetStrategyOutputTokens() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        address[] memory outputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, outputTokens);

        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.prank(randomAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                STRATEGY_MANAGER_ROLE
            )
        );
        strategyContainer.setStrategyOutputTokens(address(strategy), outputTokens);
    }

    function test_RevertIf_OutputTokensIsEmpty() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        address[] memory outputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, outputTokens);

        vm.startPrank(roles.strategyManager);
        address[] memory emptyOutputTokens = new address[](0);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        strategyContainer.setStrategyOutputTokens(address(strategy), emptyOutputTokens);
        vm.stopPrank();
    }

    function test_RevertIf_OutputTokenIsZeroAddress() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        address[] memory outputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, outputTokens);

        vm.startPrank(roles.strategyManager);
        address[] memory tokensWithZero = _createTokensArray(address(0));
        vm.expectRevert(Errors.ZeroAddress.selector);
        strategyContainer.setStrategyOutputTokens(address(strategy), tokensWithZero);
        vm.stopPrank();
    }

    function test_RevertIf_OutputTokenNotWhitelisted() public {
        address[] memory inputTokens = _createTokensArray(address(notion));
        address[] memory outputTokens = _createTokensArray(address(notion));
        _addStrategyWithTokens(address(strategy), inputTokens, outputTokens);

        vm.startPrank(roles.strategyManager);
        address nonWhitelistedToken = address(_deployMockERC20("Token", "TKN", 18));
        address[] memory tokensWithNonWhitelisted = _createTokensArray(nonWhitelistedToken);
        vm.expectRevert(abi.encodeWithSelector(IContainer.NotWhitelistedToken.selector, nonWhitelistedToken));
        strategyContainer.setStrategyOutputTokens(address(strategy), tokensWithNonWhitelisted);
        vm.stopPrank();
    }
}
