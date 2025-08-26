// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {Common} from "./libraries/helpers/Common.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IChainlinkPriceFeed {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

contract PriceOracle is Initializable, AccessControlUpgradeable, IPriceOracle {
    using Math for uint256;

    bytes32 private constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    address public accessControl;

    mapping(address => address) public tokenToChainlinkFeed;

    event PriceFeedUpdated(address token, address feed);

    error NotGovernance(address account);
    error FeedNotFound(address token);

    function initialize(address admin) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setPriceFeed(address token, address feed) external onlyRole(GOVERNANCE_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        tokenToChainlinkFeed[token] = feed;
        emit PriceFeedUpdated(token, feed);
    }

    function getPrice(address token) public view override returns (uint256, uint256) {
        require(token != address(0), Errors.ZeroAddress());
        address chainlinkFeed = tokenToChainlinkFeed[token];
        require(chainlinkFeed != address(0), FeedNotFound(token));
        int256 price = IChainlinkPriceFeed(chainlinkFeed).latestAnswer();
        uint8 decimals = IChainlinkPriceFeed(chainlinkFeed).decimals();
        require(price > 0, Errors.ZeroAmount());
        require(decimals > 0, Errors.ZeroAmount());
        return (uint256(price), uint256(decimals));
    }

    function getUsdValue(address token, uint256 amount) external view override returns (uint256) {
        (uint256 price, uint256 decimals) = getPrice(token);
        return amount.mulDiv(price, 10 ** decimals);
    }

    function getUsdValueUnified(address token, uint256 amount) external view override returns (uint256) {
        (uint256 price, uint256 decimals) = getPrice(token);
        uint256 value = amount.mulDiv(price, 10 ** decimals);
        return Common.toUnifiedDecimalsUint8(token, value);
    }
}
