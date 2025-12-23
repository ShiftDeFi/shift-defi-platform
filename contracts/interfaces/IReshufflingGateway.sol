// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBridgeAdapter} from "./IBridgeAdapter.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

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
    error NothingToWithdraw();
    error NoSharesToWithdraw();
    error VaultNotInRepairingMode();
    error VaultNotInReshufflingMode();
    error NotWhitelistedToken(address token);
    error NotWhitelistedBridgeAdapter(address bridgeAdapter);
    error WrongRemoteChainId(uint256 expected, uint256 received);
    error TokenNotWhitelistedOnContainer(address token);

    /**
     * @notice Address of the vault.
     */
    function vault() external view returns (address);

    /**
     * @notice Address of the notion token.
     */
    function notion() external view returns (address);

    /**
     * @notice Address of the swap router.
     */
    function swapRouter() external view returns (address);

    /**
     * @notice Whitelists a token for reshuffling.
     * @param token Token address.
     */
    function whitelistToken(address token) external;

    /**
     * @notice Whitelists a bridge adapter.
     * @param bridgeAdapter Bridge adapter address.
     */
    function whitelistBridgeAdapter(address bridgeAdapter) external;

    /**
     * @notice Removes a token from the whitelist.
     * @param token Token address.
     */
    function blacklistToken(address token) external;

    /**
     * @notice Removes a bridge adapter from the whitelist.
     * @param bridgeAdapter Bridge adapter address.
     */
    function blacklistBridgeAdapter(address bridgeAdapter) external;

    /**
     * @notice Claims bridged tokens from a bridge adapter.
     * @param bridgeAdapter Bridge adapter address.
     * @param token Token address.
     * @return amount Claimed amount.
     */
    function claimBridge(address bridgeAdapter, address token) external returns (uint256 amount);

    /**
     * @notice Prepares liquidity via swaps before reshuffling.
     * @param swapInstructions Swap instructions to execute.
     */
    function prepareLiquidity(ISwapRouter.SwapInstruction[] calldata swapInstructions) external;

    /**
     * @notice Sends assets to cross-chain container through bridge adapters.
     * @param container Target container address.
     * @param bridgeAdapters Bridge adapters to use.
     * @param instructions Bridge instructions matching adapters.
     */
    function sendToCrossChainContainer(
        address container,
        address[] memory bridgeAdapters,
        IBridgeAdapter.BridgeInstruction[] calldata instructions
    ) external payable;

    /**
     * @notice Sends assets to local container.
     * @param container Target container address.
     * @param tokens Tokens to send.
     * @param amounts Amounts to send per token.
     */
    function sendToLocalContainer(
        address container,
        address[] memory tokens,
        uint256[] memory amounts
    ) external payable;

    /**
     * @notice Withdraws pro-rata assets when vault is in repairing mode.
     * @param account Recipient account.
     */
    function withdraw(address account) external;
}
