// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ContainerAgent} from "contracts/ContainerAgent.sol";

contract UpgradeContainerAgent is Script {
    address private containerAgentProxy = vm.envAddress("CONTAINER_AGENT_PROXY");
    address private containerAgentProxyAdmin = vm.envAddress("CONTAINER_AGENT_PROXY_ADMIN");

    function run() public {
        bytes memory data = "";

        vm.startBroadcast();
        address newImplementation = address(new ContainerAgent());
        vm.stopBroadcast();

        bytes memory dataToSign = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(containerAgentProxy), newImplementation, data)
        );

        console.log("Data to sign:");
        console.logBytes(dataToSign);
    }
}
