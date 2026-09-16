// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

interface ICowProtocolModule {
    /**
     * @notice Emitted when the CoW Protocol adapter this contract places orders through is set.
     * @dev The previous adapter is the zero address on the first call.
     * @param previousCowAdapter The adapter that was replaced.
     * @param newCowAdapter The adapter now in use.
     */
    event CowAdapterUpdated(address indexed previousCowAdapter, address indexed newCowAdapter);

    /**
     * @notice Emitted when a CoW Protocol order is placed and its sell tokens are committed.
     * @dev The adapter's own OrderPlaced carries the identifier settlement records fills under; this
     *      event carries what the caller supplied, so an order can be attributed to this contract
     *      without reading its adapter address first.
     * @param orderDigest The order's EIP-712 digest, the key the adapter records it under.
     * @param sellToken The token the order sells.
     * @param buyToken The token the order buys.
     * @param sellAmount The exact amount of sellToken the order sells.
     * @param buyAmount The least buyToken the order accepts for it.
     * @param validTo The unix timestamp after which the order is no longer fillable.
     */
    event CowOrderPlaced(
        bytes32 indexed orderDigest,
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo
    );

    /**
     * @notice Thrown when the CoW Protocol surface is used before an adapter has been set.
     */
    error CowAdapterNotSet();

    /**
     * @notice Thrown when the adapter offered is not owned by this contract.
     * @dev An adapter's owner is immutable and only its owner may place, cancel or resolve on it,
     *      so an adapter owned by anything else is unusable here. Reading it also rejects an
     *      address carrying no code, which could otherwise be written and never replaced —
     *      replacing an adapter reads the outgoing one.
     * @param cowAdapter The adapter offered.
     */
    error CowAdapterNotOwned(address cowAdapter);

    /**
     * @notice Thrown when an order names a token this contract has not whitelisted.
     * @dev Both of an order's tokens must be whitelisted: a bought token outside the whitelist is
     *      invisible to the balance checks a batch report makes.
     * @param token The token named.
     */
    error OrderTokenNotWhitelisted(address token);

    /**
     * @notice Returns the CoW Protocol adapter address.
     * @return The address of the CoW Protocol adapter contract, or the zero address if none is set
     */
    function cowAdapter() external view returns (address);

    /**
     * @notice Returns how many orders the adapter has placed and not resolved.
     * @dev Returns zero when no adapter is set, so the caller need not read cowAdapter first.
     * @return The number of pending CoW Protocol orders
     */
    function pendingCowOrderCount() external view returns (uint256);

    /**
     * @notice Places a CoW Protocol order, committing its sell tokens to the adapter.
     * @dev Can only be called by accounts with OPERATOR_ROLE on a container, or by accounts with
     *      RESHUFFLING_EXECUTOR_ROLE on the reshuffling gateway. Settlement is asynchronous, so
     *      nothing has been bought when this returns. Both tokens must be whitelisted.
     * @param params The caller-supplied part of the order
     * @return orderDigest The order's EIP-712 digest, the key cancelCowOrder and resolveCowOrder take it by
     */
    function placeCowOrder(ICowProtocolAdapter.OrderParams calldata params) external returns (bytes32 orderDigest);

    /**
     * @notice Cancels a pending CoW Protocol order and returns its sell tokens.
     * @dev Can only be called by accounts with OPERATOR_ROLE on a container, or by accounts with
     *      RESHUFFLING_EXECUTOR_ROLE on the reshuffling gateway. Reverts if a solver filled the
     *      order first, which resolveCowOrder takes instead. An expired order stays pending until
     *      this is called.
     * @param orderDigest The EIP-712 digest of the order to cancel
     */
    function cancelCowOrder(bytes32 orderDigest) external;

    /**
     * @notice Resolves one filled CoW Protocol order, releasing its commitment.
     * @dev Can only be called by accounts with OPERATOR_ROLE on a container, or by accounts with
     *      RESHUFFLING_EXECUTOR_ROLE on the reshuffling gateway. Reverts for an order the adapter
     *      cannot establish as filled, which cancelCowOrder takes instead.
     * @param orderDigest The EIP-712 digest of the order to resolve
     */
    function resolveCowOrder(bytes32 orderDigest) external;

    /**
     * @notice Returns a token balance held by the adapter itself.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE. Recovers a donation: an order's
     *      sell tokens are held by its lane, so anything the adapter holds arrived unsolicited.
     * @param token The address of the token to return
     */
    function sweepCowAdapter(address token) external;

    /**
     * @notice Returns a token balance held by one of the adapter's lanes.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE. Recovers a balance that arrived
     *      at a lane outside an order; a lane's own order sends its leftovers back when it resolves.
     * @param laneIndex The index of the lane to sweep
     * @param token The address of the token to return
     */
    function sweepCowLane(uint256 laneIndex, address token) external;

    /**
     * @notice Sets the CoW Protocol adapter address.
     * @dev Can only be called by accounts with TOKEN_MANAGER_ROLE. Replacing a non-zero adapter
     *      requires it to carry no pending order: an order is reachable only through the adapter
     *      that placed it, so replacing one under a pending order strands it.
     * @param newCowAdapter The address of the new CoW Protocol adapter contract
     */
    function setCowAdapter(address newCowAdapter) external;
}
