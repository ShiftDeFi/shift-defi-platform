// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Script} from "forge-std/Script.sol";

contract DeploySaltedProxy is Script {
    function _proxifyWithSalt(
        address implementation,
        bytes memory data,
        address proxyAdminOwner
    ) internal returns (address) {
        bytes32 saltHash = keccak256(abi.encodePacked(implementation, block.timestamp, block.chainid));
        return address(new TransparentUpgradeableProxy{salt: saltHash}(implementation, proxyAdminOwner, data));
    }
}
