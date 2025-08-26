// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IReshufflingGateway {
    event WithdrawInRepairingMode(address indexed owner, address indexed token, uint256 amount);
    event SentToLocalContainer(address indexed container, address indexed token, uint256 amount);
    event SentToCrossChainContainer(address indexed container, address indexed token, uint256 amount);

    event TokenWhitelisted(address indexed token);
    event TokenBlacklisted(address indexed token);
    event BridgeAdapterWhitelisted(address indexed bridgeAdapter);
    event BridgeAdapterBlacklisted(address indexed bridgeAdapter);

    error NotContainer(address container);
    error NotVault(address vault);
    error VaultNotInRepairingMode();
    error VaultNotInReshufflingMode();
    error NotWhitelistedToken(address token);
    error NotWhitelistedBridgeAdapter(address bridgeAdapter);
    error WrongRemoteChainId(uint256 expected, uint256 received);
    error TokenNotWhitelistedOnContainer(address token);

    function withdraw(uint256 positionId) external;
}
