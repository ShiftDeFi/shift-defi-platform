// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {ChainlinkOracleWrapper} from "../../contracts/priceOracles/ChainlinkOracleWrapper.sol";

contract DeployChainlinkOracleWrapper is Script {
    uint256 private constant DEFAULT_PRICE_FEED_STALENESS_THRESHOLD = 1 days;
    address private defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE");
    address private oracleManager = vm.envAddress("ORACLE_MANAGER_ROLE");
    uint256 private defaultPriceFeedStalenessThreshold =
        vm.envOr("DEFAULT_PRICE_FEED_STALENESS_THRESHOLD", DEFAULT_PRICE_FEED_STALENESS_THRESHOLD);

    function run() public {
        vm.startBroadcast();
        new ChainlinkOracleWrapper(defaultAdmin, oracleManager, defaultPriceFeedStalenessThreshold);
        vm.stopBroadcast();
    }
}
