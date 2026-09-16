// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev An ERC20 that delivers less than it is asked to transfer, so a recipient measuring its own
///      balance delta sees a shortfall. Mints and burns are not charged.
contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public constant FEE_BPS = 100;
    uint256 private constant TOTAL_BPS = 10_000;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = (value * FEE_BPS) / TOTAL_BPS;
        super._update(from, to, value - fee);

        if (fee != 0) {
            super._update(from, address(0), fee);
        }
    }
}
