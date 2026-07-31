// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Vault} from "../../contracts/Vault.sol";

contract UpgradeVault is Script {
    address private vaultProxy = vm.envAddress("VAULT_PROXY");
    address private vaultProxyAdmin = vm.envAddress("VAULT_PROXY_ADMIN");

    function run() public {
        bytes memory data = "";

        vm.startBroadcast();
        address newImplementation = address(new Vault());
        vm.stopBroadcast();

        bytes memory dataToSign = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(vaultProxy), newImplementation, data)
        );

        console.log("Data to sign:");
        console.logBytes(dataToSign);
    }
}
