// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IStrategyTemplate} from "contracts/interfaces/IStrategyTemplate.sol";
import {L1Base} from "test/L1Base.t.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";

contract ContainerLocalBaseTest is L1Base {
    using stdStorage for StdStorage;

    IContainerLocal internal containerLocal;
    IStrategyTemplate internal strategy;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(roles.reshufflingManager);
        vault.enableReshufflingMode();

        containerLocal = _deployContainerLocal();
        _addContainer(address(containerLocal), block.chainid);

        vm.prank(roles.reshufflingExecutor);
        vault.disableReshufflingMode();

        strategy = _deployMockStrategy(address(containerLocal));
        MockStrategy(address(strategy)).setState(bytes32(uint256(1)), true, true, false, 1);

        vm.prank(roles.reshufflingManager);
        containerLocal.addStrategy(
            address(strategy),
            _createTokensArray(address(notion)),
            _createTokensArray(address(notion))
        );

        vm.prank(roles.reshufflingExecutor);
        containerLocal.disableReshufflingMode();

        vm.prank(roles.strategyManager);
        containerLocal.setTreasury(treasury);
    }

    function _setContainerStatus(IContainerLocal.ContainerLocalStatus status) internal {
        stdstore.target(address(containerLocal)).sig(containerLocal.status.selector).checked_write(uint256(status));
    }
}
