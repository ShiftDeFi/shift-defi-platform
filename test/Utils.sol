// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

library Utils {
    using Math for uint256;

    uint256 private constant BPS = 10000;

    function calculateMinBridgeAmount(address crossChainContainer, uint256 amount) external view returns (uint256) {
        return amount.mulDiv(ICrossChainContainer(crossChainContainer).MAX_BRIDGE_SLIPPAGE(), BPS);
    }
}
