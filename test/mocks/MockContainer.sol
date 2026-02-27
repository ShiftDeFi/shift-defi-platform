// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Container} from "contracts/Container.sol";

contract MockContainer is Container {
    constructor(address defaultAdmin_, address tokenManager_, address notion_, address swapRouter_) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin_);
        _grantRole(TOKEN_MANAGER_ROLE, tokenManager_);
        notion = notion_;
        _setSwapRouter(swapRouter_);
    }

    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Local;
    }

    function validateToken(address token) external view {
        _validateToken(token);
    }

    function validateWhitelistedTokensBeforeReport(bool ignoreNotion, bool ignoreDust) external view returns (bool) {
        return _validateWhitelistedTokensBeforeReport(ignoreNotion, ignoreDust);
    }

    function hasOnlyNotionToken() external view returns (bool) {
        return _hasOnlyNotionToken();
    }

    function dropApprovesFromWhitelistedTokens(address addr) external {
        _dropApprovesFromWhitelistedTokens(addr);
    }

    function approveWhitelistedTokens(address addr) external {
        _approveWhitelistedTokens(addr);
    }
}
