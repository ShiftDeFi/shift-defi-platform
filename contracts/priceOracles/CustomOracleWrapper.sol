// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ICustomOracleWrapper} from "../interfaces/ICustomOracleWrapper.sol";

import {Errors} from "../libraries/helpers/Errors.sol";

contract CustomOracleWrapper is AccessControl, IPriceOracle, ICustomOracleWrapper {
    bytes32 private constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 private constant FEEDER_ROLE = keccak256("FEEDER_ROLE");

    uint8 private constant DEFAULT_PRICE_DECIMALS = 8;

    mapping(address => uint256) public tokenToPrice;

    /**
     * @notice Initializes the CustomOracleWrapper contract.
     * @dev Sets up access control and grants roles to default admin and oracle manager.
     * @param defaultAdmin The address to receive DEFAULT_ADMIN_ROLE.
     * @param oracleManager The address to receive ORACLE_MANAGER_ROLE.
     */
    constructor(address defaultAdmin, address oracleManager, address feederRole) AccessControl() {
        require(defaultAdmin != address(0), Errors.ZeroAddress());
        require(oracleManager != address(0), Errors.ZeroAddress());
        require(feederRole != address(0), Errors.ZeroAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ORACLE_MANAGER_ROLE, oracleManager);
        _grantRole(FEEDER_ROLE, feederRole);
    }

    /// @inheritdoc ICustomOracleWrapper
    function whitelistFeeder(address feeder) external onlyRole(ORACLE_MANAGER_ROLE) {
        _grantRole(FEEDER_ROLE, feeder);
    }

    /// @inheritdoc ICustomOracleWrapper
    function blacklistFeeder(address feeder) external onlyRole(ORACLE_MANAGER_ROLE) {
        _revokeRole(FEEDER_ROLE, feeder);
    }

    /// @inheritdoc ICustomOracleWrapper
    function submitPrice(address token, uint256 price) external onlyRole(FEEDER_ROLE) {
        tokenToPrice[token] = price;
        emit PriceSubmitted(token, price);
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address token) external view returns (uint256, uint8) {
        return (tokenToPrice[token], DEFAULT_PRICE_DECIMALS);
    }

    /// @inheritdoc IPriceOracle
    function decimals() external pure returns (uint8) {
        return DEFAULT_PRICE_DECIMALS;
    }
}
