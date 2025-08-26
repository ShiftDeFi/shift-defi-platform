// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IVault} from "./interfaces/IVault.sol";

contract Collector is Initializable {
    using SafeERC20 for IERC20;

    IVault private _vault;
    IERC20 private _notion;

    mapping(uint256 => mapping(uint256 => bool)) public positionClaimedBatch;

    // ---- Events ----

    event Claimed(address user, uint256 positionId, uint256 amount);

    // ---- Errors ----

    error AlreadyClaimed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address vault) public initializer {
        _vault = IVault(vault);
        _notion = IVault(vault).notion();
    }

    function claim(uint256 positionId, uint256 batchId) external {
        require(!positionClaimedBatch[positionId][batchId], AlreadyClaimed());
        positionClaimedBatch[positionId][batchId] = true;

        uint256 amountToClaim = _vault.getAcceptedNotionToClaim(positionId, batchId);
        _notion.safeTransfer(msg.sender, amountToClaim);

        emit Claimed(msg.sender, positionId, batchId);
    }
}
