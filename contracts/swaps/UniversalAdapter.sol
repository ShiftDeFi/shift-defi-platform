// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {IUniversalAdapter} from "../interfaces/IUniversalAdapter.sol";

contract UniversalAdapter is AccessControl, ReentrancyGuard, ISwapAdapter, IUniversalAdapter {
    using Address for address;
    using Bytes for bytes;
    using SafeERC20 for IERC20;

    bytes32 private constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    mapping(address => mapping(address => SwapInfo)) public swapInfos;

    modifier onlyWhitelistManager() {
        require(hasRole(WHITELIST_MANAGER_ROLE, msg.sender), NotWhitelistManager(msg.sender));
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function isSwapSupported(address tokenIn, address tokenOut) external view override returns (bool) {
        return swapInfos[tokenIn][tokenOut].router != address(0) && swapInfos[tokenIn][tokenOut].payload.length > 0;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes calldata
    ) external payable override nonReentrant {
        require(swapInfos[tokenIn][tokenOut].router != address(0), NoSwapInfo(tokenIn, tokenOut));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 amountOutBefore = IERC20(tokenOut).balanceOf(address(this));
        _executeSwap(swapInfos[tokenIn][tokenOut], tokenIn, amountIn);
        uint256 amountOutAfter = IERC20(tokenOut).balanceOf(address(this));
        require(
            amountOutAfter - amountOutBefore >= minAmountOut,
            SlippageNotMet(tokenOut, amountOutAfter - amountOutBefore, minAmountOut)
        );
        IERC20(tokenOut).safeTransfer(receiver, amountOutAfter);
    }
    function setSwapInfo(
        address fromToken,
        address toToken,
        address router,
        uint256 amountIndex,
        bytes calldata payload
    ) external override onlyWhitelistManager {
        swapInfos[fromToken][toToken] = SwapInfo(router, amountIndex, payload);
        emit SwapInfoSet(fromToken, toToken, swapInfos[fromToken][toToken]);
    }

    function _executeSwap(SwapInfo memory swapInfo, address tokenIn, uint256 amountIn) private {
        bytes memory executionData = _insertData(swapInfo.payload, swapInfo.amountIndex, amountIn);
        IERC20(tokenIn).forceApprove(swapInfo.router, amountIn);
        swapInfo.router.functionCall(executionData);
    }

    function _insertData(bytes memory _data, uint256 _index, uint256 _value) private pure returns (bytes memory) {
        require(_index + 32 <= _data.length, IndexOutOfBounds(_index));
        assembly {
            // data — pointer to the beginning of the bytes structure
            // first 32 bytes: length
            // then the data
            let dataPtr := add(_data, 32) // address of the first byte of the array
            let dest := add(dataPtr, _index) // address where we write the value

            mstore(dest, _value) // write 32 bytes value starting from dest
        }
        return _data;
    }
}
