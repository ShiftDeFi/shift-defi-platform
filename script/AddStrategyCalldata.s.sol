// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {ContainerLocal} from "contracts/ContainerLocal.sol";

/// @notice Generates calldata for `ContainerLocal.addStrategy`.
///
/// Required env vars:
/// - STRATEGY: strategy contract address
/// - INPUT_TOKENS: comma-separated input token addresses
/// - OUTPUT_TOKENS: comma-separated output token addresses
///
/// Example:
/// STRATEGY=0x... INPUT_TOKENS=0x...,0x... OUTPUT_TOKENS=0x... \
///   forge script script/AddStrategyCalldata.s.sol
contract AddStrategyCalldata is Script {
    function run() external view {
        address strategy = vm.envAddress("STRATEGY");
        address[] memory inputTokens = vm.envAddress("INPUT_TOKENS", ",");
        address[] memory outputTokens = vm.envAddress("OUTPUT_TOKENS", ",");

        bytes memory calldata_ = abi.encodeCall(ContainerLocal.addStrategy, (strategy, inputTokens, outputTokens));

        console2.log("strategy:", strategy);
        console2.log("inputTokens length:", inputTokens.length);
        console2.log("outputTokens length:", outputTokens.length);
        console2.log("addStrategy calldata:");
        console2.logBytes(calldata_);
    }
}
