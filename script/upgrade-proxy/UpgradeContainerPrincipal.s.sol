// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ContainerPrincipal} from "../../contracts/ContainerPrincipal.sol";

contract UpgradeContainerPrincipal is Script {
    address private containerPrincipalProxy = vm.envAddress("CONTAINER_PRINCIPAL_PROXY");
    address private containerPrincipalProxyAdmin = vm.envAddress("CONTAINER_PRINCIPAL_PROXY_ADMIN");

    function run() public {
        bytes memory data = "";

        vm.startBroadcast();
        address newImplementation = address(new ContainerPrincipal());
        vm.stopBroadcast();

        bytes memory dataToSign = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(containerPrincipalProxy), newImplementation, data)
        );

        console.log("Data to sign:");
        console.logBytes(dataToSign);
    }
}
