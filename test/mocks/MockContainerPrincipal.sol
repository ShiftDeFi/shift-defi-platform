// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IContainerPrincipal} from "contracts/interfaces/IContainerPrincipal.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";

contract MockContainerPrincipal is IContainerPrincipal {
    using SafeERC20 for IERC20;

    address public vault;
    ContainerPrincipalStatus public status;
    uint256 public nav0;
    uint256 public nav1;
    uint256 public registeredWithdrawShareAmount;
    address public notion;
    address public swapRouter;
    address public messageRouter;
    address public peerContainer;
    uint256 public remoteChainId;
    uint256 public claimCounter;

    uint256 public constant MAX_BRIDGE_SLIPPAGE = 9000; // 10%

    constructor(address _vault, address _notion, uint256 _remoteChainId) {
        vault = _vault;
        notion = _notion;
        remoteChainId = _remoteChainId;
    }

    function containerType() external pure override returns (ContainerType) {
        return ContainerType.Principal;
    }

    function isTokenWhitelisted(address) external pure override returns (bool) {
        return true;
    }

    function whitelistToken(address) external pure override {}

    function blacklistToken(address) external pure override {}

    function setWhitelistedTokenDustThreshold(address, uint256) external pure override {}

    function setSwapRouter(address) external pure override {}

    function prepareLiquidity(ISwapRouter.SwapInstruction[] calldata) external override {}

    function setMessageRouter(address) external pure override {}

    function setPeerContainer(address _peerContainer) external override {
        peerContainer = _peerContainer;
    }

    function receiveMessage(bytes memory) external pure override {}

    function setBridgeAdapter(address, bool) external pure override {}

    function isBridgeAdapterSupported(address) external pure override returns (bool) {
        return false;
    }

    function registerDepositRequest(uint256 amount) external override {
        IERC20(notion).safeTransferFrom(vault, address(this), amount);
    }

    function registerWithdrawRequest(uint256) external pure override {}

    function sendDepositRequest(
        ICrossChainContainer.MessageInstruction memory,
        address[] calldata,
        IBridgeAdapter.BridgeInstruction[] calldata
    ) external payable override {}

    function sendWithdrawRequest(ICrossChainContainer.MessageInstruction memory) external payable override {}

    function reportDeposit() external payable override {}

    function reportWithdrawal() external payable override {}

    function claim(address, address) external pure override {}

    function claimMultiple(address[] calldata, address[] calldata) external pure override {}
}
