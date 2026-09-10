// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PriceOracleAggregator} from "contracts/PriceOracleAggregator.sol";

contract UpgradePriceOracleAggregator is Script {
    address public priceOracleAggregatorProxy = vm.envAddress("PRICE_ORACLE_AGGREGATOR_PROXY");
    address public priceOracleAggregatorProxyAdmin = vm.envAddress("PRICE_ORACLE_AGGREGATOR_PROXY_ADMIN");

    function run() public {
        bytes memory data = "";

        vm.startBroadcast();
        address newImplementation = address(new PriceOracleAggregator());
        vm.stopBroadcast();

        bytes memory dataToSign = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(priceOracleAggregatorProxy), newImplementation, data)
        );

        console.log("Data to sign:");
        console.logBytes(dataToSign);
    }
}
