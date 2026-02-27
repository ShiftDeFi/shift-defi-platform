// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract MockERC20 is IERC20Permit, ERC20 {
    uint8 private _decimals;
    mapping(address => uint256) public nonces;

    bytes public constant EIP712_REVISION = bytes("1");
    bytes32 internal constant EIP712_DOMAIN =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 public DOMAIN_SEPARATOR;

    error InvalidOwner(address owner);
    error InvalidExpiration(uint256 deadline);
    error InvalidSignature(address signer, address owner);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(EIP712_DOMAIN, keccak256(bytes(name_)), keccak256(EIP712_REVISION), block.chainid, address(this))
        );

        _setupDecimals(decimals_);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(owner != address(0), InvalidOwner(owner));
        require(block.timestamp <= deadline, InvalidExpiration(deadline));
        uint256 currentValidNonce = nonces[owner];
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, currentValidNonce, deadline))
            )
        );
        address signer = ecrecover(digest, v, r, s);
        require(signer == owner, InvalidSignature(signer, owner));
        nonces[owner] = currentValidNonce + 1;
        _approve(owner, spender, value);
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 decimals_) external {
        _setupDecimals(decimals_);
    }
}
