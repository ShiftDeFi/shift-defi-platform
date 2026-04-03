// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";

contract StrategyContainerSettersTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal strategy;
    address internal whitelistedToken;

    function setUp() public override {
        super.setUp();

        whitelistedToken = address(_deployMockERC20("Token", "TKN", 18));
        strategy = new MockStrategyInterfaceBased(address(strategyContainer));
        vm.prank(roles.tokenManager);
        strategyContainer.whitelistToken(whitelistedToken);
    }

    // ---- setReshufflingGateway tests ----

    function test_SetReshufflingGateway() public {
        address reshufflingGateway = makeAddr("NEW_RESHUFFLING_GATEWAY");
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
}
