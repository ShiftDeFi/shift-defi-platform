// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {L1Base} from "test/L1Base.t.sol";

contract BridgeAdapterBase is L1Base {
    uint256 internal constant BRIDGE_AMOUNT = 1_000 * NOTION_PRECISION;

    address BRIDGER = makeAddr("Bridger");

    function setUp() public virtual override {
        super.setUp();

        containerPrincipal = _deployContainerPrincipal();
    }
}
