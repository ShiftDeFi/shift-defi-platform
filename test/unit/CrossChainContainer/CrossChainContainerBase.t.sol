// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {MockCrossChainContainer} from "test/mocks/MockCrossChainContainer.sol";

import {L1Base} from "test/L1Base.t.sol";

abstract contract CrossChainContainerBaseTest is L1Base {
    MockCrossChainContainer internal crossChainContainer;

    uint256 internal constant EXPECTED_TOKEN_AMOUNT_SLOT = 10;

    function setUp() public virtual override {
        super.setUp();

        containerPrincipal = _deployContainerPrincipal();
        crossChainContainer = _deployMockCrossChainContainer();

        vm.startPrank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(address(crossChainContainer));
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(notion));
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(crossChainContainer));
        vm.stopPrank();

        assertEq(crossChainContainer.messageRouter(), address(messageRouter), "test_SetUp: message router mismatch");
        assertEq(crossChainContainer.remoteChainId(), REMOTE_CHAIN_ID, "test_SetUp: remote chain id mismatch");
    }
}
