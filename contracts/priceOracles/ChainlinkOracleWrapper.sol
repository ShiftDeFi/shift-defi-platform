// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IChainlinkPriceFeed} from "../dependencies/interfaces/chainlink/IChainlinkPriceFeed.sol";
import {IChainlinkOracleWrapper} from "../interfaces/IChainlinkOracleWrapper.sol";

contract ChainlinkOracleWrapper is AccessControl, IPriceOracle, IChainlinkOracleWrapper {
    bytes32 private constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    mapping(address => address) public tokenToChainlinkFeed;

    constructor(address defaultAdmin, address oracleManager) AccessControl() {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ORACLE_MANAGER_ROLE, oracleManager);
    }

    /// @inheritdoc IChainlinkOracleWrapper
    function setChainlinkFeed(address token, address feed) external override onlyRole(ORACLE_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(feed != address(0), Errors.ZeroAddress());

        tokenToChainlinkFeed[token] = feed;

        emit ChainlinkFeedSet(token, feed);
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address token) external view override returns (uint256, uint8) {
        require(token != address(0), Errors.ZeroAddress());
        address chainlinkFeed = tokenToChainlinkFeed[token];
        require(chainlinkFeed != address(0), ChainlinkFeedNotFound(token));

        int256 price = IChainlinkPriceFeed(chainlinkFeed).latestAnswer();
        require(price > 0, ZeroPrice(token));

        return (uint256(price), IChainlinkPriceFeed(chainlinkFeed).decimals());
    }

    function decimals() external pure override returns (uint8) {
        revert Errors.NotImplemented();
    }
}
