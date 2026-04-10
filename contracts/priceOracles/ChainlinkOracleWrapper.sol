// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {AggregatorV3Interface} from "../dependencies/interfaces/chainlink/AggregatorV3Interface.sol";
import {IChainlinkOracleWrapper} from "../interfaces/IChainlinkOracleWrapper.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

import {Errors} from "../libraries/Errors.sol";

contract ChainlinkOracleWrapper is AccessControl, IPriceOracle, IChainlinkOracleWrapper {
    bytes32 private constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    uint256 public defaultPriceFeedStalenessThreshold;
    mapping(address => uint256) public priceFeedStalenessThreshold;

    mapping(address => address) public tokenToChainlinkFeed;

    constructor(
        address defaultAdmin,
        address oracleManager,
        uint256 _defaultPriceFeedStalenessThreshold
    ) AccessControl() {
        require(defaultAdmin != address(0), Errors.ZeroAddress());
        require(oracleManager != address(0), Errors.ZeroAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ORACLE_MANAGER_ROLE, oracleManager);

        require(_defaultPriceFeedStalenessThreshold > 0, ZeroStalenessThreshold());
        defaultPriceFeedStalenessThreshold = _defaultPriceFeedStalenessThreshold;
    }

    /// @inheritdoc IChainlinkOracleWrapper
    function setChainlinkFeed(address token, address feed) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(feed != address(0), Errors.ZeroAddress());

        _getAndValidateLatestRoundData(token, feed);

        tokenToChainlinkFeed[token] = feed;

        emit ChainlinkFeedSet(token, feed);
    }

    /// @inheritdoc IChainlinkOracleWrapper
    function setPriceFeedStalenessThreshold(address token, uint256 threshold) external onlyRole(ORACLE_MANAGER_ROLE) {
        _setPriceFeedStalenessThreshold(token, threshold);
    }

    function _setPriceFeedStalenessThreshold(address token, uint256 threshold) internal {
        require(token != address(0), Errors.ZeroAddress());
        require(threshold > 0, ZeroStalenessThreshold());
        uint256 previousThreshold = priceFeedStalenessThreshold[token];
        priceFeedStalenessThreshold[token] = threshold;
        emit PriceFeedStalenessThresholdUpdated(token, previousThreshold, threshold);
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address token) external view returns (uint256, uint8) {
        require(token != address(0), Errors.ZeroAddress());
        address chainlinkFeed = tokenToChainlinkFeed[token];
        require(chainlinkFeed != address(0), ChainlinkFeedNotFound(token));

        uint256 price = _getAndValidateLatestRoundData(token, chainlinkFeed);

        return (price, AggregatorV3Interface(chainlinkFeed).decimals());
    }

    function decimals() external pure returns (uint8) {
        revert Errors.NotImplemented();
    }

    function _getAndValidateLatestRoundData(address token, address feed) internal view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = AggregatorV3Interface(feed).latestRoundData();
        require(price > 0, ZeroPrice(token));

        uint256 stalenessThreshold = priceFeedStalenessThreshold[token];
        stalenessThreshold = stalenessThreshold == 0 ? defaultPriceFeedStalenessThreshold : stalenessThreshold;
        require(
            block.timestamp - updatedAt <= stalenessThreshold,
            StalePriceFeed(token, updatedAt, stalenessThreshold)
        );

        return uint256(price);
    }
}
