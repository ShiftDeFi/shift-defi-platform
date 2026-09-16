// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICowProtocolAdapter} from "@shift-defi/cow-protocol-adapter/src/interfaces/ICowProtocolAdapter.sol";

contract MockCowProtocolAdapter is ICowProtocolAdapter {
    uint256 internal _pendingOrderCount;
    mapping(bytes32 => bool) internal _placed;
    uint256 internal _deployedLaneCount;
    address internal _owner;

    /// @dev The real adapter takes its owner at construction and keeps it immutable, so a test
    ///      that wires one up states the owner the same way. setOwner stays for the tests that
    ///      need it to be wrong.
    constructor(address owner_) {
        _owner = owner_;
    }

    function setOwner(address newOwner) external {
        _owner = newOwner;
    }

    function setDeployedLaneCount(uint256 newDeployedLaneCount) external {
        _deployedLaneCount = newDeployedLaneCount;
    }

    function setPendingOrderCount(uint256 newPendingOrderCount) external {
        _pendingOrderCount = newPendingOrderCount;
    }

    function pendingOrderCount() external view returns (uint256) {
        return _pendingOrderCount;
    }

    function placeOrder(OrderParams calldata params) external returns (bytes32) {
        IERC20(params.sellToken).transferFrom(msg.sender, address(this), params.sellAmount);

        bytes32 orderDigest = keccak256(abi.encode(params));
        _placed[orderDigest] = true;

        return orderDigest;
    }

    function resolveOrder(bytes32 orderDigest) external {
        require(_placed[orderDigest], OrderUnknown(orderDigest));
    }

    function requireNoPendingOrders() external {
        require(_pendingOrderCount == 0, OrdersStillPending(_pendingOrderCount));
    }

    function cancelOrder(bytes32 orderDigest) external {
        require(_placed[orderDigest], OrderUnknown(orderDigest));
    }

    function sweep(address token) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, NothingToSweep());

        IERC20(token).transfer(_owner, balance);
    }

    function sweepLane(uint256 laneIndex, address token) external {
        require(laneIndex < _deployedLaneCount, LaneIndexOutOfRange(laneIndex, _deployedLaneCount));

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, NothingToSweep());

        IERC20(token).transfer(_owner, balance);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function isValidSignatureForLane(address, bytes32) external view returns (bytes4) {}

    function orderUid(OrderParams calldata, uint256) external view returns (bytes memory) {}

    function orderUidOf(bytes32) external view returns (bytes memory) {}

    function nextLane(address) external view returns (address, uint256) {}

    function laneAt(uint256) external view returns (address) {}

    function laneOccupancy(address) external view returns (uint256) {}

    function deployedLaneCount() external view returns (uint256) {
        return _deployedLaneCount;
    }

    function laneImplementation() external view returns (address) {}

    function orderRecord(bytes32) external view returns (OrderRecord memory) {}

    function fillVerdict(bytes32) external view returns (FillVerdict, uint256) {}

    function pendingOrderDigests() external view returns (bytes32[] memory) {}

    function settlement() external view returns (address) {}

    function vaultRelayer() external view returns (address) {}

    function domainSeparator() external view returns (bytes32) {}
}
