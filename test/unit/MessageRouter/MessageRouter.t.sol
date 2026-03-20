// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MessageRouter} from "contracts/MessageRouter.sol";
import {IMessageRouter} from "contracts/interfaces/IMessageRouter.sol";

import {RingCacheLibrary} from "contracts/libraries/RingCacheLibrary.sol";

import {L1Base} from "test/L1Base.t.sol";

contract MessageRouterTest is L1Base {
    uint256 internal constant NONCE_SLOT = 0;
    uint256 internal constant PATHS_SLOT = 1;
    uint256 internal constant MESSAGE_ADAPTERS_SLOT = 2;

    function setUp() public virtual override {
        super.setUp();

        address implementation = address(new MessageRouter());
        address proxy = _proxify(
            roles.deployer,
            implementation,
            roles.defaultAdmin,
            abi.encodeWithSelector(
                MessageRouter.initialize.selector,
                roles.defaultAdmin,
                roles.whitelistManager,
                roles.cacheManager,
                MAX_CACHE_SIZE
            )
        );

        /// @dev Overwrite MockMessageRouter for this specific test
        messageRouter = IMessageRouter(proxy);
    }

    function _getNonce() internal view returns (uint256) {
        return uint256(vm.load(address(messageRouter), bytes32(NONCE_SLOT)));
    }

    function _getPathData(bytes32 path) internal view returns (IMessageRouter.PathData memory) {
        bytes32 baseSlot = keccak256(abi.encode(path, PATHS_SLOT));

        IMessageRouter.PathData memory pathData;

        pathData.lastNonce = uint256(vm.load(address(messageRouter), baseSlot));
        pathData.chainId = uint256(vm.load(address(messageRouter), bytes32(uint256(baseSlot) + 1)));
        pathData.sender = address(uint160(uint256(vm.load(address(messageRouter), bytes32(uint256(baseSlot) + 2)))));

        uint256 receiverAndIsWhitelisted = uint256(vm.load(address(messageRouter), bytes32(uint256(baseSlot) + 3)));

        pathData.receiver = address(uint160(receiverAndIsWhitelisted));
        pathData.isWhitelisted = ((receiverAndIsWhitelisted >> 160) & 0xFF) != 0;

        return pathData;
    }

    function _isMessageAdapterWhitelisted(address adapter) internal view returns (bool) {
        bytes32 slot = keccak256(abi.encode(adapter, MESSAGE_ADAPTERS_SLOT));
        return vm.load(address(messageRouter), slot) != 0;
    }

    function _prepareSendMessage(
        address _adapter,
        bytes memory _adapterParameters,
        address _sender,
        address _receiver,
        uint256 _chainId,
        bytes memory _message
    ) internal returns (IMessageRouter.SendParams memory) {
        vm.startPrank(roles.whitelistManager);
        messageRouter.whitelistMessageAdapter(_adapter);
        messageRouter.whitelistPath(_sender, _receiver, _chainId);
        vm.stopPrank();

        return
            IMessageRouter.SendParams({
                adapter: _adapter,
                chainTo: _chainId,
                adapterParameters: _adapterParameters,
                message: _message
            });
    }

    function _prepareReceiveMessage(
        uint256 nonce,
        address sender,
        bytes memory message
    ) internal returns (bytes32, bytes memory) {
        uint256 chainTo = block.chainid + 1;
        address containerPrincipal = address(_deployMockContainerPrincipal());

        bytes32 path = messageRouter.calculatePath(sender, containerPrincipal, chainTo);
        bytes memory rawMessageWithPathAndNonce = messageRouter.encodeMessage(nonce, path, message);

        vm.startPrank(roles.whitelistManager);
        messageRouter.whitelistMessageAdapter(address(messageAdapter));
        messageRouter.whitelistPath(sender, containerPrincipal, chainTo);
        vm.stopPrank();

        return (path, rawMessageWithPathAndNonce);
    }

    function test_CalculatePath() public view {
        bytes32 path = messageRouter.calculatePath(address(this), address(this), block.chainid);
        assertEq(
            path,
            keccak256(abi.encode(address(this), address(this), block.chainid)),
            "test_CalculatePath: path mismatch"
        );
    }

    function test_EncodeMessage() public view {
        uint256 nonce = _getNonce();
        bytes32 path = messageRouter.calculatePath(address(this), address(this), block.chainid);
        bytes memory message = abi.encode("test");
        bytes memory encodedMessage = messageRouter.encodeMessage(nonce, path, message);
        assertEq(
            abi.encodePacked(nonce, path, message),
            encodedMessage,
            "test_EncodeMessage: encoded message mismatch"
        );
    }

    function test_CalculateCacheKey() public view {
        uint256 nonce = _getNonce();
        bytes32 path = messageRouter.calculatePath(address(this), address(this), block.chainid);
        bytes memory message = abi.encode("test");
        bytes memory encodedMessage = messageRouter.encodeMessage(nonce, path, message);
        assertEq(
            keccak256(abi.encode(block.chainid, encodedMessage)),
            messageRouter.calculateCacheKey(block.chainid, encodedMessage),
            "test_CalculateCacheKey: cache key mismatch"
        );
    }

    function test_DecodeMessage() public view {
        uint256 nonce = _getNonce();
        bytes32 path = messageRouter.calculatePath(address(this), address(this), block.chainid);
        bytes memory message = abi.encode("test");
        bytes memory encodedMessage = messageRouter.encodeMessage(nonce, path, message);

        (uint256 decodedNonce, bytes32 decodedPath, bytes memory decodedMessage) = messageRouter.decodeMessage(
            encodedMessage
        );

        assertEq(decodedNonce, nonce, "test_DecodeMessage: nonce mismatch");
        assertEq(decodedPath, path, "test_DecodeMessage: path mismatch");
        assertEq(decodedMessage, message, "test_DecodeMessage: message mismatch");
    }

    function test_RevertIf_DecodeMessageWithZeroLengthPayload() public {
        bytes memory zeroLengthMessage = abi.encodePacked(bytes32(0), bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.MessageTooShort.selector, zeroLengthMessage.length));
        vm.prank(roles.whitelistManager);
        messageRouter.decodeMessage(zeroLengthMessage);
    }

    function test_RevertIf_DecodedMessageIsTooShort() public {
        bytes32 part1 = bytes32(0);
        bytes31 part2 = bytes31(0);
        bytes memory shortMessage = abi.encodePacked(part1, part2);
        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.MessageTooShort.selector, shortMessage.length));
        messageRouter.decodeMessage(shortMessage);
    }

    function test_WhitelistPath() public {
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainId = block.chainid + 1;
        bytes32 path = messageRouter.calculatePath(sender, receiver, chainId);

        vm.prank(roles.whitelistManager);
        messageRouter.whitelistPath(sender, receiver, chainId);

        IMessageRouter.PathData memory pathData = _getPathData(path);
        assertEq(pathData.lastNonce, 0, "test_WhitelistPath: last nonce mismatch");
        assertEq(pathData.chainId, chainId, "test_WhitelistPath: chain id mismatch");
        assertEq(pathData.sender, sender, "test_WhitelistPath: sender mismatch");
        assertEq(pathData.receiver, receiver, "test_WhitelistPath: receiver mismatch");
        assertTrue(pathData.isWhitelisted, "test_WhitelistPath: is whitelisted mismatch");
    }

    function test_WhitelistPath_RevertIf_PathAlreadyWhitelisted() public {
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainId = block.chainid + 1;
        bytes32 path = messageRouter.calculatePath(sender, receiver, chainId);

        vm.prank(roles.whitelistManager);
        messageRouter.whitelistPath(sender, receiver, chainId);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.PathAlreadyWhitelisted.selector, path));
        vm.prank(roles.whitelistManager);
        messageRouter.whitelistPath(sender, receiver, chainId);
    }

    function test_BlacklistPath() public {
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainId = block.chainid + 1;
        bytes32 path = messageRouter.calculatePath(sender, receiver, chainId);

        vm.prank(roles.whitelistManager);
        messageRouter.whitelistPath(sender, receiver, chainId);

        vm.prank(roles.whitelistManager);
        messageRouter.blacklistPath(sender, receiver, chainId);

        IMessageRouter.PathData memory pathData = _getPathData(path);
        assertFalse(pathData.isWhitelisted, "test_BlacklistPath: is whitelisted mismatch");
    }

    function test_RevertIf_BlacklistNotWhitelistedPath() public {
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainId = block.chainid + 1;
        bytes32 path = messageRouter.calculatePath(sender, receiver, chainId);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.PathNotWhitelisted.selector, path));
        vm.prank(roles.whitelistManager);
        messageRouter.blacklistPath(sender, receiver, chainId);
    }

    function test_WhitelistMessageAdapter() public {
        address adapter = address(0x123);
        vm.prank(roles.whitelistManager);
        messageRouter.whitelistMessageAdapter(adapter);

        assertTrue(_isMessageAdapterWhitelisted(adapter), "test_WhitelistMessageAdapter: is whitelisted mismatch");
    }

    function test_RevertIf_WhitelistMessageAdapterAlreadyWhitelisted() public {
        address adapter = address(0x123);
        vm.prank(roles.whitelistManager);
        messageRouter.whitelistMessageAdapter(adapter);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.AdapterAlreadyWhitelisted.selector, adapter));
        vm.prank(roles.whitelistManager);
        messageRouter.whitelistMessageAdapter(adapter);
    }

    function test_BlacklistMessageAdapter() public {
        address adapter = address(0x123);
        vm.prank(roles.whitelistManager);
        messageRouter.whitelistMessageAdapter(adapter);

        vm.prank(roles.whitelistManager);
        messageRouter.blacklistMessageAdapter(adapter);

        assertFalse(_isMessageAdapterWhitelisted(adapter), "test_BlacklistMessageAdapter: is whitelisted mismatch");
    }

    function test_RevertIf_BlacklistMessageAdapterNotWhitelisted() public {
        address adapter = address(0x123);
        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.AdapterNotWhitelisted.selector, adapter));
        vm.prank(roles.whitelistManager);
        messageRouter.blacklistMessageAdapter(adapter);
    }

    function test_SendMessage() public {
        uint256 nonce = _getNonce();
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainTo = block.chainid + 1;
        bytes memory message = abi.encode("test");

        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            sender,
            receiver,
            chainTo,
            message
        );

        uint256 value = 1 ether;
        hoax(sender, value);
        messageRouter.send{value: value}(receiver, sendParams);

        uint256 expectedNonce = nonce + 1;
        bytes32 remotePath = messageRouter.calculatePath(sender, receiver, block.chainid);

        assertEq(_getNonce(), expectedNonce, "test_SendMessage: nonce mismatch");
        assertTrue(
            messageRouter.isMessageCached(chainTo, expectedNonce, remotePath, message),
            "test_SendMessage: message not cached"
        );
        assertEq(address(messageAdapter).balance, value, "test_SendMessage: message adapter balance mismatch");
    }

    function test_RevertIf_SendMessageMessageAdapterNotWhitelisted() public {
        address receiver = address(0x456);
        uint256 chainTo = block.chainid + 1;
        bytes memory message = abi.encode("test");
        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            receiver,
            receiver,
            chainTo,
            message
        );

        vm.prank(roles.whitelistManager);
        messageRouter.blacklistMessageAdapter(address(messageAdapter));

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.AdapterNotWhitelisted.selector, address(messageAdapter)));
        messageRouter.send(receiver, sendParams);
    }

    function test_RevertIf_SendMessagePathNotWhitelisted() public {
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainTo = block.chainid + 1;
        bytes memory message = abi.encode("test");

        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            sender,
            receiver,
            chainTo,
            message
        );

        address incorrectSender = address(0x789);
        bytes32 incorrectSenderPath = messageRouter.calculatePath(incorrectSender, receiver, chainTo);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.PathNotWhitelisted.selector, incorrectSenderPath));
        vm.prank(incorrectSender);
        messageRouter.send(receiver, sendParams);
    }

    function test_ReceiveMessage() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        bytes memory message = "test";
        (bytes32 path, bytes memory rawMessageWithPathAndNonce) = _prepareReceiveMessage(nonce, sender, message);

        vm.prank(address(messageAdapter));
        messageRouter.receiveMessage(rawMessageWithPathAndNonce);

        IMessageRouter.PathData memory pathData = _getPathData(path);
        assertEq(pathData.lastNonce, nonce, "test_ReceiveMessage: nonce mismatch");
        assertEq(address(messageAdapter).balance, 0, "test_ReceiveMessage: message adapter balance should be zero");
    }

    function test_RevertIf_ReceiveMessageWithIncorrectNonce() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        bytes memory message = "test";
        (bytes32 path, bytes memory rawMessageWithPathAndNonce) = _prepareReceiveMessage(nonce, sender, message);

        vm.prank(address(messageAdapter));
        messageRouter.receiveMessage(rawMessageWithPathAndNonce);
        IMessageRouter.PathData memory pathData = _getPathData(path);
        assertEq(pathData.lastNonce, nonce, "test_ReceiveMessage: nonce mismatch");

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.ReplayCheckFailed.selector, nonce));
        vm.prank(address(messageAdapter));
        messageRouter.receiveMessage(rawMessageWithPathAndNonce);
    }

    function test_RevertIf_ReceiveMessageWithNotWhitelistedAdapter() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        address notWhitelistedAdapter = address(0x456);
        bytes memory message = "test";
        (, bytes memory rawMessageWithPathAndNonce) = _prepareReceiveMessage(nonce, sender, message);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.AdapterNotWhitelisted.selector, notWhitelistedAdapter));
        vm.prank(notWhitelistedAdapter);
        messageRouter.receiveMessage(rawMessageWithPathAndNonce);
    }

    function test_RevertIf_ReceiveMessageWithNotWhitelistedPath() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        bytes memory message = "test";
        (, bytes memory rawMessageWithPathAndNonce) = _prepareReceiveMessage(nonce, sender, message);

        bytes32 path = messageRouter.calculatePath(sender, address(this), block.chainid + 1);
        rawMessageWithPathAndNonce = messageRouter.encodeMessage(nonce, path, message);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.PathNotWhitelisted.selector, path));
        vm.prank(address(messageAdapter));
        messageRouter.receiveMessage(rawMessageWithPathAndNonce);
    }

    function test_RetryMessageFromCache() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainId = block.chainid + 1;
        bytes memory message = "test";

        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            sender,
            receiver,
            chainId,
            message
        );

        vm.prank(sender);
        messageRouter.send(receiver, sendParams);
        uint256 expectedNonce = _getNonce();

        bytes32 remotePath = messageRouter.calculatePath(sender, receiver, block.chainid);
        assertTrue(
            messageRouter.isMessageCached(chainId, nonce, remotePath, message),
            "test_RetryMessageFromCache: message should be cached before retry"
        );

        uint256 value = 1 ether;
        hoax(roles.cacheManager, value);
        messageRouter.retryCachedMessage{value: value}(nonce, remotePath, sendParams);

        assertEq(_getNonce(), expectedNonce, "test_RetryMessageFromCache: nonce mismatch");
        assertTrue(
            messageRouter.isMessageCached(chainId, nonce, remotePath, message),
            "test_RetryMessageFromCache: message should remain cached"
        );
        assertEq(
            address(messageAdapter).balance,
            value,
            "test_RetryMessageFromCache: message adapter balance mismatch"
        );
    }

    function test_RevertIf_RetryMessageFromCacheMessageAdapterNotWhitelisted() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainId = block.chainid + 1;
        bytes memory message = "test";
        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            sender,
            receiver,
            chainId,
            message
        );

        vm.prank(roles.whitelistManager);
        messageRouter.blacklistMessageAdapter(address(messageAdapter));

        bytes32 remotePath = messageRouter.calculatePath(sender, receiver, block.chainid);

        vm.expectRevert(abi.encodeWithSelector(IMessageRouter.AdapterNotWhitelisted.selector, address(messageAdapter)));
        vm.prank(roles.cacheManager);
        messageRouter.retryCachedMessage(nonce, remotePath, sendParams);
    }

    function test_RevertIf_RetryNotCachedMessage() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainTo = block.chainid + 1;
        bytes memory message = "test";
        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            sender,
            receiver,
            chainTo,
            message
        );

        bytes32 remotePath = messageRouter.calculatePath(sender, receiver, block.chainid);
        bytes32 cacheId = keccak256("SEND_CACHE");
        bytes memory messageWithNonceAndPath = messageRouter.encodeMessage(nonce, remotePath, message);
        bytes32 cachedKey = messageRouter.calculateCacheKey(chainTo, messageWithNonceAndPath);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLibrary.DoesNotExists.selector, cacheId, cachedKey));
        vm.prank(roles.cacheManager);
        messageRouter.retryCachedMessage(nonce, remotePath, sendParams);
    }

    function test_RemoveMessageFromCache() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainTo = block.chainid + 1;
        bytes memory message = "test";
        IMessageRouter.SendParams memory sendParams = _prepareSendMessage(
            address(messageAdapter),
            "",
            sender,
            receiver,
            chainTo,
            message
        );

        vm.prank(sender);
        messageRouter.send(receiver, sendParams);

        bytes32 remotePath = messageRouter.calculatePath(sender, receiver, block.chainid);
        assertTrue(
            messageRouter.isMessageCached(chainTo, nonce, remotePath, message),
            "test_RemoveMessageFromCache: message should be cached before remove"
        );

        vm.prank(roles.cacheManager);
        messageRouter.removeMessageFromCache(nonce, chainTo, remotePath, message);

        assertFalse(
            messageRouter.isMessageCached(chainTo, nonce, remotePath, message),
            "test_RemoveMessageFromCache: message should not be cached after remove"
        );

        bytes32 cacheId = keccak256("SEND_CACHE");
        bytes memory messageWithNonceAndPath = messageRouter.encodeMessage(nonce, remotePath, message);
        bytes32 cachedKey = messageRouter.calculateCacheKey(chainTo, messageWithNonceAndPath);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLibrary.DoesNotExists.selector, cacheId, cachedKey));
        vm.prank(roles.cacheManager);
        messageRouter.retryCachedMessage(nonce, remotePath, sendParams);
    }

    function test_RevertIf_RemoveNotCachedMessage() public {
        uint256 nonce = 1;
        address sender = address(0x123);
        address receiver = address(0x456);
        uint256 chainTo = block.chainid + 1;
        bytes memory message = "test";

        bytes32 remotePath = messageRouter.calculatePath(sender, receiver, block.chainid);
        bytes32 cacheId = keccak256("SEND_CACHE");
        bytes memory messageWithNonceAndPath = messageRouter.encodeMessage(nonce, remotePath, message);
        bytes32 cachedKey = messageRouter.calculateCacheKey(chainTo, messageWithNonceAndPath);

        vm.expectRevert(abi.encodeWithSelector(RingCacheLibrary.DoesNotExists.selector, cacheId, cachedKey));
        vm.prank(roles.cacheManager);
        messageRouter.removeMessageFromCache(nonce, chainTo, remotePath, message);
    }
}
