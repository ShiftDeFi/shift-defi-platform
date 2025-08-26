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

    event BridgeSent(address indexed token, uint256 amount, uint256 chain);
    event Bridged(address indexed claimer, address indexed token, uint256 amount);
    event Claimed(address indexed claimer, address indexed token, uint256 amount);
    event BridgePathUpdated(address indexed src, uint256 indexed chain, address indexed dst);
    event PeerUpdated(uint256 indexed chain, address indexed peer);
    event BridgerWhitelisted(address indexed bridger);
    event BridgerBlacklisted(address indexed bridger);

    error PeerNotSet(uint256 chainId);
    error BadBridgePath(address srcToken, uint256 chainTo);
    error BridgerNotWhitelisted(address bridger);

    function bridge(BridgeInstruction calldata bridgeInstruction, address receiver) external returns (uint256);

    function claim(address token) external;

    function bridgePaths(address token, uint256 chain) external view returns (address);

    function retryBridge(BridgeInstruction calldata instruction, address receiver) external;
}
