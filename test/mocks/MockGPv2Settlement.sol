// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGPv2Settlement} from "@shift-defi/cow-protocol-adapter/src/interfaces/IGPv2Settlement.sol";

/**
 * @dev Stands in for CoW Protocol's GPv2Settlement, which targets solc 0.7.6 and cannot be
 *      compiled into this tree. CowProtocolAdapter's constructor reads vaultRelayer and
 *      domainSeparator and rejects a zero for either, so both answer non-zero here.
 *
 *      This contract is its own vault relayer, so settle spends the allowance the lane granted
 *      without a second address in the way.
 */
contract MockGPv2Settlement is IGPv2Settlement {
    using SafeERC20 for IERC20;

    mapping(bytes32 => uint256) internal _filledAmount;

    /// @inheritdoc IGPv2Settlement
    function invalidateOrder(bytes calldata orderUid) external {
        _filledAmount[keccak256(orderUid)] = type(uint256).max;
    }

    /**
     * @dev Settles an order the way a solver would: the sell tokens are pulled off the lane with
     *      the relayer allowance, the buy tokens go to the order's receiver, and the fill is
     *      recorded in sell units. The buy tokens must be minted here first.
     * @param orderUid The order's unique identifier, from ICowProtocolAdapter.orderUidOf.
     * @param lane The lane holding the sell tokens.
     * @param sellToken The token the order sells.
     * @param sellAmount The amount pulled off the lane, which is what the fill is recorded as.
     * @param buyToken The token the order buys.
     * @param buyAmount The amount delivered to the receiver.
     * @param receiver The order's receiver, which the adapter sets to its own owner.
     */
    function settle(
        bytes calldata orderUid,
        address lane,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        address receiver
    ) external {
        _filledAmount[keccak256(orderUid)] = sellAmount;

        IERC20(sellToken).safeTransferFrom(lane, address(this), sellAmount);
        IERC20(buyToken).safeTransfer(receiver, buyAmount);
    }

    /// @inheritdoc IGPv2Settlement
    function filledAmount(bytes calldata orderUid) external view returns (uint256) {
        return _filledAmount[keccak256(orderUid)];
    }

    /// @inheritdoc IGPv2Settlement
    function vaultRelayer() external view returns (address) {
        return address(this);
    }

    /// @inheritdoc IGPv2Settlement
    function domainSeparator() external pure returns (bytes32) {
        return keccak256("MockGPv2Settlement");
    }
}
