// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BridgeAdapter} from "../BridgeAdapter.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {IAcrossV3Receiver} from "../dependencies/interfaces/across-v3/IAcrossV3Receiver.sol";
import {ISpookyPool} from "../dependencies/interfaces/across-v3/ISpookyPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @custom:oz-upgrades-from contracts/bridgeAdapters/AcrossBridgeAdapter.sol:AcrossBridgeAdapter
contract AcrossBridgeAdapter is BridgeAdapter, IAcrossV3Receiver {
    using Math for uint256;

    address public override spookyPool;
    uint256 public feeCapPct;
    uint256 public constant MAX_FEE_CAP_BPS = 10_000; // 100%

    function initialize(
        address _defaultAdmin,
        address _governance,
        address _spookyPool,
        uint256 _feeCapPct
    ) external initializer {
        __BridgeAdapter_init(_defaultAdmin, _governance);
        _setAcrossSpookyPool(_spookyPool);
        _setFeeCapPct(_feeCapPct);
    }

    function setSpookyPool(address spookyPoolAddress) external onlyRole(GOVERNANCE_ROLE) {
        _setAcrossSpookyPool(spookyPoolAddress);
    }

    function setFeeCapPct(uint256 feeCapPct) external onlyRole(GOVERNANCE_ROLE) {
        _setFeeCapPct(feeCapPct);
    }

    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external {
        require(msg.sender == spookyPool, OnlySpookyPool(msg.sender, spookyPool));
        _finalizeBridge(abi.decode(message, (address)), token, amount);
    }

    function _bridge(BridgeInstruction calldata instruction, bytes memory message) internal override returns (uint256) {
        AcrossParams memory acrossPayload = abi.decode(instruction.payload, (AcrossParams));

        _validatePayload(instruction, acrossPayload);

        IERC20(instruction.token).approve(spookyPool, instruction.amount);
        uint256 minAmount = instruction.amount - acrossPayload.fee;
        ISpookyPool(spookyPool).depositV3Now(
            address(this),
            peers[instruction.chainTo],
            instruction.token,
            bridgePaths[instruction.token][instruction.chainTo],
            instruction.amount,
            minAmount,
            instruction.chainTo,
            acrossPayload.exclusiveRelayer,
            ISpookyPool(spookyPool).fillDeadlineBuffer(),
            acrossPayload.exclusiveDeadline,
            message
        );
        return minAmount;
    }

    function _validatePayload(BridgeInstruction calldata instruction, AcrossParams memory acrossParams) internal view {
        require(
            acrossParams.fillDeadline >= block.timestamp,
            DeadlineExceeded(uint32(block.timestamp), acrossParams.fillDeadline)
        );
        require(acrossParams.fee * MAX_FEE_CAP_BPS < feeCapPct * instruction.amount, FeeTooHigh(acrossParams.fee));
    }

    function _setAcrossSpookyPool(address newSpookyPool) private {
        require(newSpookyPool != address(0), Errors.ZeroAddress());
        address oldPool = address(spookyPool);
        require(oldPool != newSpookyPool, Errors.AlreadySet());
        spookyPool = newSpookyPool;
        emit SpookyPoolUpdated(oldPool, newSpookyPool);
    }

    function _setFeeCapPct(uint256 newFeeCapPct) private {
        require(newFeeCapPct <= MAX_FEE_CAP_BPS, InvalidFeeCapPct(newFeeCapPct));
        uint256 oldFeeCapPct = feeCapPct;
        require(oldFeeCapPct != newFeeCapPct, Errors.AlreadySet());
        feeCapPct = newFeeCapPct;
        emit FeeCapPctUpdated(oldFeeCapPct, newFeeCapPct);
    }
}
