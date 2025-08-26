// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAccessControlManager {
    function isEmergencyRole(address account) external view returns (bool);
    function isGovernanceRole(address account) external view returns (bool);
    function isMigratorRole(address account) external view returns (bool);
    function isExecutorRole(address account) external view returns (bool);
    function isHarvesterRole(address account) external view returns (bool);
    function isStrategyManagerRole(address account) external view returns (bool);
}
