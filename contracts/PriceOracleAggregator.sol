// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Errors} from "./libraries/helpers/Errors.sol";
import {Common} from "./libraries/helpers/Common.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceOracleAggregator} from "./interfaces/IPriceOracleAggregator.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract PriceOracleAggregator is Initializable, AccessControlUpgradeable, IPriceOracleAggregator {
    using Math for uint256;

    bytes32 private constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    uint8 private constant DEFAULT_PRICE_DECIMALS = 8;
    uint256 private constant DEFAULT_PRICE_PRECISION = 10 ** DEFAULT_PRICE_DECIMALS;

    mapping(address => address) public override priceOracles;

    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address governance) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNANCE_ROLE, governance);
    }
    function setPriceOracle(address token, address priceOracle) external override onlyRole(GOVERNANCE_ROLE) {
        require(token != address(0), Errors.ZeroAddress());
        require(priceOracle != address(0), Errors.ZeroAddress());
        priceOracles[token] = priceOracle;
        emit PriceOracleSet(token, priceOracle);
    }

    function fetchTokenPrice(address token) external view override returns (uint256) {
        require(priceOracles[token] != address(0), Errors.ZeroAddress());
        (uint256 price, uint8 decimals) = IPriceOracle(priceOracles[token]).getPrice(token);
        return _normalizePrice(price, decimals);
    }

    function getRelativeValueUnified(address token0, address token1, uint256 value0) external view returns (uint256) {
        address priceOracle0 = priceOracles[token0];
        address priceOracle1 = priceOracles[token1];
        require(priceOracle0 != address(0), Errors.ZeroAddress());
        require(priceOracle1 != address(0), Errors.ZeroAddress());

        (uint256 price0, uint8 decimals0) = IPriceOracle(priceOracle0).getPrice(token0);
        (uint256 price1, uint8 decimals1) = IPriceOracle(priceOracle1).getPrice(token1);

        uint256 normalizedAmount = Common.toUnifiedDecimalsUint8(token0, value0);
        return
            normalizedAmount.mulDiv(
                _normalizePrice(price0, decimals0),
                _normalizePrice(price1, decimals1),
                Math.Rounding.Floor
            );
    }

    function _normalizePrice(uint256 price, uint8 decimals) internal view returns (uint256) {
        if (decimals > DEFAULT_PRICE_DECIMALS) {
            return price / 10 ** (decimals - DEFAULT_PRICE_DECIMALS);
        } else if (decimals < DEFAULT_PRICE_DECIMALS) {
            return price * 10 ** (DEFAULT_PRICE_DECIMALS - decimals);
        } else {
            return price;
        }
    }
}
