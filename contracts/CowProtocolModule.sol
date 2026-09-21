// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

import {ICowProtocolModule} from "./interfaces/ICowProtocolModule.sol";

import {Errors} from "./libraries/Errors.sol";

abstract contract CowProtocolModule is ICowProtocolModule {
    using SafeERC20 for IERC20;

    /// @dev No initializer grants this role; DEFAULT_ADMIN_ROLE grants it after deployment.
    bytes32 internal constant COW_SWAP_MANAGER_ROLE = keccak256("COW_SWAP_MANAGER_ROLE");

    /// @custom:storage-location erc7201:shift-defi.storage.CowProtocolModule
    struct CowProtocolModuleStorage {
        address cowAdapter;
    }

    // keccak256(abi.encode(uint256(keccak256("shift-defi.storage.CowProtocolModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COW_PROTOCOL_MODULE_STORAGE_LOCATION =
        0xb1aa910183d3e5ac328c3438d73926401ffb70f6cb60c61b67543b5deb26bb00;

    /// @inheritdoc ICowProtocolModule
    function cowAdapter() external view returns (address) {
        return _getCowProtocolModuleStorage().cowAdapter;
    }

    /// @inheritdoc ICowProtocolModule
    function pendingCowOrderCount() external view returns (uint256) {
        address cowAdapterCached = _getCowProtocolModuleStorage().cowAdapter;

        if (cowAdapterCached == address(0)) {
            return 0;
        }

        return ICowProtocolAdapter(cowAdapterCached).pendingOrderCount();
    }

    /**
     * @dev Sets the adapter this module places orders through. Replacing a non-zero adapter
     *      requires the outgoing one to carry no pending order, and the incoming one must name
     *      this contract as its owner.
     * @param newCowAdapter The address of the new CoW Protocol adapter contract.
     */
    function _setCowAdapter(address newCowAdapter) internal {
        require(newCowAdapter != address(0), Errors.ZeroAddress());
        require(ICowProtocolAdapter(newCowAdapter).owner() == address(this), CowAdapterNotOwned(newCowAdapter));

        CowProtocolModuleStorage storage $ = _getCowProtocolModuleStorage();
        address previousCowAdapter = $.cowAdapter;

        if (previousCowAdapter != address(0)) {
            uint256 pendingOrders = ICowProtocolAdapter(previousCowAdapter).pendingOrderCount();
            require(pendingOrders == 0, Errors.PendingCowOrders(address(this), pendingOrders));
        }

        $.cowAdapter = newCowAdapter;

        emit CowAdapterUpdated(previousCowAdapter, newCowAdapter);
    }

    /**
     * @dev Places an order and commits its sell tokens to the adapter. Both tokens must be
     *      whitelisted, and the approval is exact and carries no trailing zero. The remaining
     *      fields of `params` are the adapter's to validate.
     * @param params The caller-supplied part of the order.
     * @return The order's EIP-712 digest.
     */
    function _placeCowOrder(ICowProtocolAdapter.OrderParams calldata params) internal returns (bytes32) {
        address cowAdapterCached = _requireCowAdapter();

        require(_isCowTokenWhitelisted(params.sellToken), OrderTokenNotWhitelisted(params.sellToken));
        require(_isCowTokenWhitelisted(params.buyToken), OrderTokenNotWhitelisted(params.buyToken));

        IERC20(params.sellToken).forceApprove(cowAdapterCached, params.sellAmount);

        bytes32 orderDigest = ICowProtocolAdapter(cowAdapterCached).placeOrder(params);

        emit CowOrderPlaced(
            orderDigest,
            params.sellToken,
            params.buyToken,
            params.sellAmount,
            params.buyAmount,
            params.validTo
        );

        return orderDigest;
    }

    /**
     * @dev Cancels a pending order, retracting it at settlement and returning its sell tokens.
     *      Reverts through the adapter for an order a solver has already filled.
     * @param orderDigest The EIP-712 digest of the order to cancel.
     */
    function _cancelCowOrder(bytes32 orderDigest) internal {
        ICowProtocolAdapter(_requireCowAdapter()).cancelOrder(orderDigest);
    }

    /**
     * @dev Resolves one filled order, releasing its commitment and draining its lane to this
     *      contract. Reverts through the adapter for an order it cannot establish as filled.
     * @param orderDigest The EIP-712 digest of the order to resolve.
     */
    function _resolveCowOrder(bytes32 orderDigest) internal {
        ICowProtocolAdapter(_requireCowAdapter()).resolveOrder(orderDigest);
    }

    /**
     * @dev Returns a token balance held by the adapter itself to this contract.
     * @param token The token to return.
     */
    function _sweepCowAdapter(address token) internal {
        ICowProtocolAdapter(_requireCowAdapter()).sweep(token);
    }

    /**
     * @dev Returns a token balance held by one of the adapter's lanes to this contract.
     * @param laneIndex The lane to sweep.
     * @param token The token to return.
     */
    function _sweepCowLane(uint256 laneIndex, address token) internal {
        ICowProtocolAdapter(_requireCowAdapter()).sweepLane(laneIndex, token);
    }

    /**
     * @dev Resolves every filled order the adapter has placed and reverts unless none is left
     *      pending, draining each lane to this contract as it goes. Returns without calling out
     *      when no adapter is set.
     */
    function _requireNoPendingOrders() internal {
        address cowAdapterCached = _getCowProtocolModuleStorage().cowAdapter;

        if (cowAdapterCached == address(0)) {
            return;
        }

        ICowProtocolAdapter(cowAdapterCached).requireNoPendingOrders();
    }

    /**
     * @dev The adapter this module places orders through, reverting if none is set.
     * @return The adapter address, never zero.
     */
    function _requireCowAdapter() internal view returns (address) {
        address cowAdapterCached = _getCowProtocolModuleStorage().cowAdapter;
        require(cowAdapterCached != address(0), CowAdapterNotSet());

        return cowAdapterCached;
    }

    /**
     * @dev Whether a token may be named by an order. Implemented by the contract inheriting this
     *      module.
     * @param token The token to check.
     * @return True where the token is whitelisted.
     */
    function _isCowTokenWhitelisted(address token) internal view virtual returns (bool);

    /**
     * @dev Resolves the ERC-7201 namespace this module keeps its state in.
     * @return The module's namespaced storage.
     */
    function _getCowProtocolModuleStorage() internal pure returns (CowProtocolModuleStorage storage) {
        CowProtocolModuleStorage storage $;
        assembly {
            $.slot := COW_PROTOCOL_MODULE_STORAGE_LOCATION
        }
        return $;
    }
}
