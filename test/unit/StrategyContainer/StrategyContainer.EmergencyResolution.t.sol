// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyContainerBaseTest} from "test/unit/StrategyContainer/StrategyContainerBase.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IStrategyContainer} from "contracts/interfaces/IStrategyContainer.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";

contract StrategyContainerEmergencyResolutionTest is StrategyContainerBaseTest {
    MockStrategyInterfaceBased internal strategy;

    function setUp() public override {
        super.setUp();
        (strategy, , ) = _createAndAddStrategyWithTokens(1, 1, true);
    }

    function test_StartEmergencyResolution() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        assertTrue(
            strategyContainer.isResolvingEmergency(),
            "test_StartEmergencyResolution: Emergency resolution not started"
        );
        assertTrue(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_StartEmergencyResolution: Strategy NAV not unresolved"
        );

        uint256 bitmask = strategyContainer.getStrategyUnresolvedNavBitmask();
        assertGt(bitmask, 0, "test_StartEmergencyResolution: Bitmask not greater than 0");
    }

    function test_RevertIf_NotStrategyInStartEmergencyResolution() public {
        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        strategyContainer.startEmergencyResolution();
    }

    function test_MultipleCallsInStartEmergencyResolution() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        uint256 bitmaskAfterFirstCall = strategyContainer.getStrategyUnresolvedNavBitmask();

        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        assertTrue(
            strategyContainer.isResolvingEmergency(),
            "test_MultipleCallsInStartEmergencyResolution: Emergency resolution not started"
        );
        assertTrue(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_MultipleCallsInStartEmergencyResolution: Strategy NAV not unresolved"
        );

        uint256 bitmaskAfterSecondCall = strategyContainer.getStrategyUnresolvedNavBitmask();
        assertEq(
            bitmaskAfterFirstCall,
            bitmaskAfterSecondCall,
            "test_MultipleCallsInStartEmergencyResolution: Bitmask not equal"
        );
    }

    function test_CompleteEmergencyResolution() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        uint256 resolvedNav = vm.randomUint(1e18, 1000e18);
        vm.prank(address(strategy));
        strategyContainer.resolveStrategyNav(resolvedNav);

        vm.prank(roles.emergencyManager);
        strategyContainer.completeEmergencyResolution();

        assertFalse(
            strategyContainer.isResolvingEmergency(),
            "test_CompleteEmergencyResolution: Emergency resolution not completed"
        );
    }

    function test_RevertIf_NotResolvingEmergencyInCompleteEmergencyResolution() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        uint256 resolvedNav = vm.randomUint(1e18, 1000e18);
        vm.prank(address(strategy));
        strategyContainer.resolveStrategyNav(resolvedNav);
        vm.prank(roles.emergencyManager);
        strategyContainer.completeEmergencyResolution();
        vm.prank(roles.emergencyManager);
        vm.expectRevert(IStrategyContainer.NotResolvingEmergency.selector);
        strategyContainer.completeEmergencyResolution();
    }

    function test_RevertIf_StrategyNavUnresolvedInCompleteEmergencyResolution() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        vm.expectRevert(
            abi.encodeWithSelector(
                IStrategyContainer.EmergencyResolutionNotCompleted.selector,
                strategyContainer.getStrategyUnresolvedNavBitmask()
            )
        );
        vm.prank(roles.emergencyManager);
        strategyContainer.completeEmergencyResolution();
    }

    function test_RevertIf_UnauthorizedCallInCompleteEmergencyResolution() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        uint256 resolvedNav = vm.randomUint(1e18, 1000e18);
        vm.prank(address(strategy));
        strategyContainer.resolveStrategyNav(resolvedNav);

        address randomAddress = makeAddr("RANDOM_ADDRESS");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomAddress,
                EMERGENCY_MANAGER_ROLE
            )
        );
        vm.prank(randomAddress);
        strategyContainer.completeEmergencyResolution();
    }

    // ---- resolveStrategyNav tests ----

    function test_ResolveStrategyNav_Success() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        uint256 initialBitmask = strategyContainer.getStrategyUnresolvedNavBitmask();
        assertGt(initialBitmask, 0, "test_ResolveStrategyNav_Success: Initial bitmask should be greater than 0");
        assertTrue(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_ResolveStrategyNav_Success: Strategy NAV should be unresolved"
        );

        uint256 resolvedNav = vm.randomUint(1e18, 1000e18);
        vm.prank(address(strategy));
        strategyContainer.resolveStrategyNav(resolvedNav);

        assertFalse(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_ResolveStrategyNav_Success: Strategy NAV should be resolved"
        );

        uint256 finalBitmask = strategyContainer.getStrategyUnresolvedNavBitmask();
        assertEq(finalBitmask, 0, "test_ResolveStrategyNav_Success: Final bitmask should be 0");
    }

    function test_RevertIf_NotStrategyInResolveStrategyNav() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        address nonStrategy = makeAddr("NON_STRATEGY");
        uint256 resolvedNav = vm.randomUint(1e18, 1000e18);

        vm.expectRevert(IStrategyContainer.StrategyNotFound.selector);
        vm.prank(nonStrategy);
        strategyContainer.resolveStrategyNav(resolvedNav);
    }

    function test_RevertIf_AlreadyResolvedInResolveStrategyNav() public {
        vm.prank(address(strategy));
        strategyContainer.startEmergencyResolution();

        uint256 resolvedNav = vm.randomUint(1e18, 1000e18);
        vm.prank(address(strategy));
        strategyContainer.resolveStrategyNav(resolvedNav);

        assertFalse(
            strategyContainer.isStrategyNavUnresolved(address(strategy)),
            "test_RevertIf_AlreadyResolvedInResolveStrategyNav: Strategy NAV should be resolved"
        );

        vm.expectRevert(
            abi.encodeWithSelector(IStrategyContainer.StrategyNavAlreadyResolved.selector, address(strategy))
        );
        vm.prank(address(strategy));
        strategyContainer.resolveStrategyNav(resolvedNav);
    }
}
