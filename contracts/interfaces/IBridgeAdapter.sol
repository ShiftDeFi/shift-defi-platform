// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBridgeAdapter {
    struct BridgeInstruction {
        uint256 chainTo;
        uint256 amount;
        uint256 minTokenAmount;
        address token;
        bytes payload;
    }

    event BridgeSent(address indexed token, uint256 amount, uint256 indexed chain);
    event Bridged(address indexed claimer, address indexed token, uint256 amount);
    event Claimed(address indexed claimer, address indexed token, uint256 amount);
    event BridgePathUpdated(address indexed src, uint256 indexed chain, address indexed dst);
    event PeerUpdated(uint256 indexed chain, address indexed peer);
    event BridgerWhitelisted(address indexed bridger);
    event BridgerBlacklisted(address indexed bridger);
    event SlippageCapPctUpdated(uint256 slippageCapPct);

    error PeerNotSet(uint256 chainId);
    error BadBridgePath(address srcToken, uint256 chainTo);
    error BridgerNotWhitelisted(address bridger);
    error SlippageCapExceeded(uint256 slippageDeltaPct, uint256 slippageCapPct);

    /*
     * @dev Bridges the token from the source chain to the destination chain.
     * @param bridgeInstruction The instruction for the bridge.
     * @param receiver The address to receive the bridged token on the destination chain.
     * @return The amount of the bridged token.
     */
    function bridge(BridgeInstruction calldata bridgeInstruction, address receiver) external returns (uint256);

    /*
     * @dev Claims the bridged token from the bridge adapter.
     * @param token The token to claim.
     * @return The amount of the claimed token.
     */
    function claim(address token) external returns (uint256);

    /*
     * @dev Returns the matched token address on the destination chain.
     * @param token The token to bridge on source chain.
     * @param chain The destination chain to bridge to.
     * @return The token address on the destination chain.
     */
    function bridgePaths(address token, uint256 chain) external view returns (address);
    /*
     * @dev Returns the peer address for a given chain.
     * @param chain The chain to get the peer address for.
     * @return The peer address.
     */
    function peers(uint256 chain) external view returns (address);
    /*
     * @dev Returns the whitelist status for a given bridger.
     * @param bridger The address of the bridger.
     * @return The whitelist status.
     */
    function whitelistedBridgers(address bridger) external view returns (bool);
    /*
     * @dev Returns the claimable amount for a given claimer and token.
     * @param claimer The address of the claimer.
     * @param token The token address.
     * @return The claimable amount.
     */
    function claimableAmounts(address claimer, address token) external view returns (uint256);

    /*
     * @dev Sets the bridge path for a given token and chain.
     * @param token The token to bridge on source chain.
     * @param chain The destination chain to bridge to.
     * @param path The path to bridge the token.
     */
    function setBridgePath(address token, uint256 chain, address path) external;

    /*
     * @dev Retries the bridge for a given instruction and receiver.
     * @param instruction The instruction for the bridge.
     * @param receiver The address to receive the bridged token on the destination chain.
     */
    function retryBridge(BridgeInstruction calldata instruction, address receiver) external;
}
