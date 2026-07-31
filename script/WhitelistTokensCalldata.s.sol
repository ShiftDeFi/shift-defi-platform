// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {IContainer} from "contracts/interfaces/IContainer.sol";

/// @notice Generates calldata for `ContainerLocal.whitelistToken` for USDC, RLUSD and PYUSD.
///
/// Required env vars:
/// - USDC: USDC token address
/// - RLUSD: RLUSD token address
/// - PYUSD: PYUSD token address
///
/// Example:
/// USDC=0x... RLUSD=0x... PYUSD=0x... \
///   forge script script/WhitelistTokensCalldata.s.sol
contract WhitelistTokensCalldata is Script {
    function run() external view {
        address usdc = vm.envAddress("USDC");
        address rlusd = vm.envAddress("RLUSD");
        address pyusd = vm.envAddress("PYUSD");

        _logWhitelistCalldata("USDC", usdc);
        _logWhitelistCalldata("RLUSD", rlusd);
        _logWhitelistCalldata("PYUSD", pyusd);
    }

    function _logWhitelistCalldata(string memory name, address token) internal pure {
        bytes memory calldata_ = abi.encodeCall(IContainer.whitelistToken, (token));

        console2.log("---");
        console2.log(name, token);
        console2.log("whitelistToken calldata:");
        console2.logBytes(calldata_);
    }
}
