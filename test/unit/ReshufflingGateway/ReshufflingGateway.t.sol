// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {L1Base} from "test/L1Base.t.sol";

import {IReshufflingGateway} from "contracts/interfaces/IReshufflingGateway.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {IBridgeAdapter} from "contracts/interfaces/IBridgeAdapter.sol";
import {IContainerLocal} from "contracts/interfaces/IContainerLocal.sol";
import {IContainer} from "contracts/interfaces/IContainer.sol";
import {ICrossChainContainer} from "contracts/interfaces/ICrossChainContainer.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Errors} from "contracts/libraries/helpers/Errors.sol";

contract ReshufflingGatewayTest is L1Base {
    using Math for uint256;

    IContainerLocal containerLocal;

    function setUp() public override {
        super.setUp();

        containerPrincipal = _deployMockContainerPrincipal();
        containerLocal = _deployMockContainerLocal();

        _addContainer(address(containerPrincipal), REMOTE_CHAIN_ID);
        _addContainer(address(containerLocal), block.chainid);

        containerPrincipal.setPeerContainer(makeAddr("ContainerAgent"));

        vm.startPrank(roles.whitelistManager);
        swapRouter.whitelistSwapAdapter(address(mockSwapAdapter));
        reshufflingGateway.whitelistBridgeAdapter(address(bridgeAdapter));
        reshufflingGateway.whitelistToken(address(notion));
        vm.stopPrank();

        vm.startPrank(roles.bridgeAdapterManager);
        bridgeAdapter.whitelistBridger(address(reshufflingGateway));
        bridgeAdapter.setBridgePath(address(notion), REMOTE_CHAIN_ID, address(notion));
        bridgeAdapter.setPeer(REMOTE_CHAIN_ID, address(this));
        vm.stopPrank();
    }

    function _craftSwapInstructions(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (ISwapRouter.SwapInstruction[] memory) {
        ISwapRouter.SwapInstruction[] memory swapInstructions = new ISwapRouter.SwapInstruction[](1);
        swapInstructions[0] = ISwapRouter.SwapInstruction({
            adapter: address(mockSwapAdapter),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            payload: "0x"
        });
        return swapInstructions;
    }

    function _setReshufflingMode() internal {
        vm.startPrank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));
        vault.setReshufflingMode(true);
        vm.stopPrank();
    }

    function test_WhitelistToken() public {
        address token = makeAddr("TOKEN");

        vm.expectEmit();
        emit IReshufflingGateway.TokenWhitelisted(token);

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistToken(token);
    }

    function test_RevertIf_WhitelistToken_ZeroAddress() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        reshufflingGateway.whitelistToken(address(0));
    }

    function test_RevertIf_WhitelistToken_AlreadyWhitelisted() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(IReshufflingGateway.AlreadyWhitelistedToken.selector);
        reshufflingGateway.whitelistToken(address(notion));
    }

    function test_BlacklistToken() public {
        address token = makeAddr("TOKEN");

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistToken(token);

        vm.expectEmit();
        emit IReshufflingGateway.TokenBlacklisted(token);

        vm.prank(roles.whitelistManager);
        reshufflingGateway.blacklistToken(token);
    }

    function test_RevertIf_BlacklistToken_ZeroAddress() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        reshufflingGateway.blacklistToken(address(0));
    }

    function test_RevertIf_BlacklistToken_NotWhitelisted() public {
        address notWhitelistedToken = makeAddr("NOT_WHITELISTED_TOKEN");

        vm.prank(roles.whitelistManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedToken.selector, notWhitelistedToken));
        reshufflingGateway.blacklistToken(notWhitelistedToken);
    }

    function test_WhitelistBridgeAdapter() public {
        address _bridgeAdapter = makeAddr("BRIDGE_ADAPTER");

        vm.expectEmit();
        emit IReshufflingGateway.BridgeAdapterWhitelisted(_bridgeAdapter);

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistBridgeAdapter(_bridgeAdapter);
    }

    function test_RevertIf_WhitelistBridgeAdapter_ZeroAddress() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        reshufflingGateway.whitelistBridgeAdapter(address(0));
    }

    function test_RevertIf_WhitelistBridgeAdapter_AlreadyWhitelisted() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(IReshufflingGateway.AlreadyWhitelistedBridgeAdapter.selector);
        reshufflingGateway.whitelistBridgeAdapter(address(bridgeAdapter));
    }

    function test_BlacklistBridgeAdapter() public {
        address _bridgeAdapter = makeAddr("BRIDGE_ADAPTER");

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistBridgeAdapter(_bridgeAdapter);

        vm.expectEmit();
        emit IReshufflingGateway.BridgeAdapterBlacklisted(_bridgeAdapter);

        vm.prank(roles.whitelistManager);
        reshufflingGateway.blacklistBridgeAdapter(_bridgeAdapter);
    }

    function test_RevertIf_BlacklistBridgeAdapter_ZeroAddress() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        reshufflingGateway.blacklistBridgeAdapter(address(0));
    }

    function test_RevertIf_BlacklistBridgeAdapter_NotWhitelisted() public {
        address notWhitelistedBridgeAdapter = makeAddr("NOT_WHITELISTED_BRIDGE_ADAPTER");

        vm.prank(roles.whitelistManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReshufflingGateway.NotWhitelistedBridgeAdapter.selector,
                notWhitelistedBridgeAdapter
            )
        );
        reshufflingGateway.blacklistBridgeAdapter(notWhitelistedBridgeAdapter);
    }

    function test_SetSwapRouter() public {
        address newSwapRouter = makeAddr("NEW_SWAP_ROUTER");
        address previousSwapRouter = reshufflingGateway.swapRouter();

        vm.prank(roles.whitelistManager);
        reshufflingGateway.setSwapRouter(newSwapRouter);

        assertEq(reshufflingGateway.swapRouter(), newSwapRouter);
        assertEq(IERC20(notion).allowance(address(reshufflingGateway), previousSwapRouter), 0);
    }

    function test_RevertIf_SetSwapRouter_ZeroAddress() public {
        vm.prank(roles.whitelistManager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        reshufflingGateway.setSwapRouter(address(0));
    }

    function test_ClaimBridge() public {
        uint256 amount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);

        notion.mint(address(bridgeAdapter), amount);
        bridgeAdapter.finalizeBridge(address(reshufflingGateway), address(notion), amount);
        reshufflingGateway.claimBridge(address(bridgeAdapter), address(notion));
        assertEq(
            notion.balanceOf(address(reshufflingGateway)),
            amount,
            "test_ClaimBridge: reshuffling gateway balance mismatch"
        );
        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            0,
            "test_ClaimBridge: bridge adapter balance should be zero"
        );
    }

    function test_RevertIf_ClaimBridge_NotWhitelistedBridgeAdapter() public {
        address notWhitelistedBridgeAdapter = makeAddr("NOT_WHITELISTED_BRIDGE_ADAPTER");
        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReshufflingGateway.NotWhitelistedBridgeAdapter.selector,
                notWhitelistedBridgeAdapter
            )
        );
        reshufflingGateway.claimBridge(notWhitelistedBridgeAdapter, makeAddr("NOT_WHITELISTED_TOKEN"));
    }

    function test_RevertIf_ClaimBridge_NotWhitelistedToken() public {
        address notWhitelistedToken = makeAddr("NOT_WHITELISTED_TOKEN");
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedToken.selector, notWhitelistedToken));
        reshufflingGateway.claimBridge(address(bridgeAdapter), notWhitelistedToken);
    }

    function test_PrepareLiquidity() public {
        uint256 amount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        uint256 expectedAmount = amount;

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistToken(address(dai));

        notion.mint(address(reshufflingGateway), amount);
        dai.mint(address(swapRouter), expectedAmount);

        vm.prank(roles.reshufflingManager);
        reshufflingGateway.prepareLiquidity(
            _craftSwapInstructions(address(notion), address(dai), amount, expectedAmount - 1)
        );

        assertEq(
            notion.balanceOf(address(reshufflingGateway)),
            0,
            "test_PrepareLiquidity: notion balance should be zero"
        );
        assertEq(
            dai.balanceOf(address(reshufflingGateway)),
            expectedAmount,
            "test_PrepareLiquidity: dai balance mismatch"
        );
    }

    function test_RevertIf_PrepareLiquidity_NotWhitelistedTokenOut() public {
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedToken.selector, address(dai)));
        reshufflingGateway.prepareLiquidity(
            _craftSwapInstructions(address(notion), address(dai), vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT), 0)
        );
    }

    function test_RevertIf_PrepareLiquidity_NotWhitelistedTokenIn() public {
        address notWhitelistedToken = makeAddr("NOT_WHITELISTED_TOKEN");

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedToken.selector, notWhitelistedToken));
        reshufflingGateway.prepareLiquidity(
            _craftSwapInstructions(notWhitelistedToken, address(dai), vm.randomUint(1e6, 10_000_000 * 1e18), 0)
        );
    }

    function test_RevertIf_PrepareLiquidity_ZeroArrayLength() public {
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        reshufflingGateway.prepareLiquidity(new ISwapRouter.SwapInstruction[](0));
    }

    function test_SendToCrossChainContainer() public {
        _setReshufflingMode();

        uint256 bridgeAmount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);

        notion.mint(address(reshufflingGateway), bridgeAmount);

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = IBridgeAdapter.BridgeInstruction({
            token: address(notion),
            amount: bridgeAmount,
            minTokenAmount: bridgeAmount.mulDiv(DEFAULT_SLIPPAGE_CAP_PCT, MAX_SLIPPAGE_CAP_PCT),
            chainTo: REMOTE_CHAIN_ID,
            payload: "0x"
        });

        vm.prank(roles.reshufflingManager);
        reshufflingGateway.sendToCrossChainContainer(address(containerPrincipal), bridgeAdapters, instructions);

        assertEq(
            notion.balanceOf(address(bridgeAdapter)),
            bridgeAmount,
            "test_SendToCrossChainContainer: bridge adapter balance mismatch"
        );
        assertEq(
            notion.balanceOf(address(reshufflingGateway)),
            0,
            "test_SendToCrossChainContainer: reshuffling gateway balance should be zero"
        );
    }

    function test_RevertIf_SendToCrossChainContainer_NotBridgeAdaptersPassed() public {
        _setReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        reshufflingGateway.sendToCrossChainContainer(
            address(containerPrincipal),
            new address[](0),
            new IBridgeAdapter.BridgeInstruction[](0)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_VaultNotInReshufflingMode() public {
        vm.prank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IReshufflingGateway.VaultNotInReshufflingMode.selector);
        reshufflingGateway.sendToCrossChainContainer(
            address(containerPrincipal),
            new address[](1),
            new IBridgeAdapter.BridgeInstruction[](1)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_InconsistentBridgeAdaptersAndInstructionsLengths() public {
        _setReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        reshufflingGateway.sendToCrossChainContainer(
            address(containerPrincipal),
            new address[](1),
            new IBridgeAdapter.BridgeInstruction[](2)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_NotPrincipalContainer() public {
        _setReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.IncorrectContainerType.selector,
                address(containerLocal),
                uint8(IContainer.ContainerType.Principal),
                uint8(IContainer.ContainerType.Local)
            )
        );
        reshufflingGateway.sendToCrossChainContainer(
            address(containerLocal),
            new address[](1),
            new IBridgeAdapter.BridgeInstruction[](1)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_NotContainer() public {
        _setReshufflingMode();

        address notVaultContainer = address(_deployMockContainerPrincipal());

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotContainer.selector, notVaultContainer));
        reshufflingGateway.sendToCrossChainContainer(
            notVaultContainer,
            new address[](1),
            new IBridgeAdapter.BridgeInstruction[](1)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_AgentNotSet() public {
        vm.mockCall(
            address(containerPrincipal),
            abi.encodeWithSelector(ICrossChainContainer.peerContainer.selector),
            abi.encode(address(0))
        );

        _setReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IReshufflingGateway.IncorrectPeerContainer.selector, address(containerPrincipal))
        );
        reshufflingGateway.sendToCrossChainContainer(
            address(containerPrincipal),
            new address[](1),
            new IBridgeAdapter.BridgeInstruction[](1)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_NotWhitelistedBridgeAdapter() public {
        _setReshufflingMode();

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = makeAddr("NOT_WHITELISTED_BRIDGE_ADAPTER");

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedBridgeAdapter.selector, bridgeAdapters[0])
        );
        reshufflingGateway.sendToCrossChainContainer(
            address(containerPrincipal),
            bridgeAdapters,
            new IBridgeAdapter.BridgeInstruction[](1)
        );
    }

    function test_RevertIf_SendToCrossChainContainer_NotWhitelistedTokenIn() public {
        _setReshufflingMode();

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        address notWhitelistedToken = makeAddr("NOT_WHITELISTED_TOKEN");
        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = IBridgeAdapter.BridgeInstruction({
            token: notWhitelistedToken,
            amount: vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT),
            minTokenAmount: 0,
            chainTo: REMOTE_CHAIN_ID,
            payload: "0x"
        });

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedToken.selector, notWhitelistedToken));
        reshufflingGateway.sendToCrossChainContainer(address(containerPrincipal), bridgeAdapters, instructions);
    }

    function test_RevertIf_SendToCrossChainContainer_WrongRemoteChainId() public {
        _setReshufflingMode();

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        uint256 wrongChainId = vm.randomUint(1, 1000);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = IBridgeAdapter.BridgeInstruction({
            token: address(notion),
            amount: vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT),
            minTokenAmount: 0,
            chainTo: wrongChainId,
            payload: "0x"
        });

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IReshufflingGateway.WrongRemoteChainId.selector, wrongChainId, REMOTE_CHAIN_ID)
        );
        reshufflingGateway.sendToCrossChainContainer(address(containerPrincipal), bridgeAdapters, instructions);
    }

    function test_RevertIf_SendToCrossChainContainer_TokenNotWhitelistedOnContainer() public {
        _setReshufflingMode();

        uint256 amount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);

        MockERC20 token = _deployMockERC20("Token", "TKN", 18);
        token.mint(address(reshufflingGateway), amount);

        vm.prank(roles.whitelistManager);
        reshufflingGateway.whitelistToken(address(token));

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = IBridgeAdapter.BridgeInstruction({
            token: address(token),
            amount: amount,
            minTokenAmount: 0,
            chainTo: REMOTE_CHAIN_ID,
            payload: "0x"
        });

        vm.mockCall(
            address(containerPrincipal),
            abi.encodeWithSelector(IContainer.isTokenWhitelisted.selector, address(token)),
            abi.encode(false)
        );

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IReshufflingGateway.TokenNotWhitelistedOnContainer.selector, address(token))
        );
        reshufflingGateway.sendToCrossChainContainer(address(containerPrincipal), bridgeAdapters, instructions);
    }

    function test_RevertIf_SendToCrossChainContainer_IncorrectAmount() public {
        _setReshufflingMode();

        uint256 amount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = IBridgeAdapter.BridgeInstruction({
            token: address(notion),
            amount: amount,
            minTokenAmount: 0,
            chainTo: REMOTE_CHAIN_ID,
            payload: "0x"
        });

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughTokens.selector, address(notion), amount, 0));
        reshufflingGateway.sendToCrossChainContainer(address(containerPrincipal), bridgeAdapters, instructions);
    }

    function test_RevertIf_SendToCrossChainContainer_SlippageExceeded() public {
        _setReshufflingMode();

        uint256 amount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        uint256 bridgedAmount = amount - 1;

        notion.mint(address(reshufflingGateway), amount);

        IBridgeAdapter.BridgeInstruction[] memory instructions = new IBridgeAdapter.BridgeInstruction[](1);
        instructions[0] = IBridgeAdapter.BridgeInstruction({
            token: address(notion),
            amount: amount,
            minTokenAmount: amount,
            chainTo: REMOTE_CHAIN_ID,
            payload: "0x"
        });

        address[] memory bridgeAdapters = new address[](1);
        bridgeAdapters[0] = address(bridgeAdapter);

        address peerContainer = ICrossChainContainer(address(containerPrincipal)).peerContainer();

        vm.mockCall(
            address(bridgeAdapter),
            abi.encodeWithSelector(IBridgeAdapter.bridge.selector, instructions[0], peerContainer),
            abi.encode(bridgedAmount)
        );

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IReshufflingGateway.NotEnoughTokensBridged.selector,
                address(notion),
                amount,
                bridgedAmount
            )
        );
        reshufflingGateway.sendToCrossChainContainer(address(containerPrincipal), bridgeAdapters, instructions);
    }

    function test_SendToLocalContainer() public {
        _setReshufflingMode();

        uint256 amount = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);

        notion.mint(address(reshufflingGateway), amount);

        address[] memory tokens = new address[](1);
        tokens[0] = address(notion);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(roles.reshufflingManager);
        reshufflingGateway.sendToLocalContainer(address(containerLocal), tokens, amounts);

        assertEq(
            notion.balanceOf(address(containerLocal)),
            amount,
            "test_SendToLocalContainer: container local balance mismatch"
        );
        assertEq(
            notion.balanceOf(address(reshufflingGateway)),
            0,
            "test_SendToLocalContainer: reshuffling gateway balance should be zero"
        );
    }

    function test_RevertIf_SendToLocalContainer_NotReshufflingMode() public {
        vm.startPrank(roles.emergencyManager);
        vault.setReshufflingGateway(address(reshufflingGateway));
        vm.stopPrank();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(IReshufflingGateway.VaultNotInReshufflingMode.selector);
        reshufflingGateway.sendToLocalContainer(address(containerLocal), new address[](1), new uint256[](1));
    }

    function test_RevertIf_SendToLocalContainer_ArrayLengthMismatch() public {
        _setReshufflingMode();
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        reshufflingGateway.sendToLocalContainer(address(containerLocal), new address[](1), new uint256[](2));
    }

    function test_RevertIf_SendToLocalContainer_NotContainer() public {
        _setReshufflingMode();

        address notContainer = makeAddr("NOT_CONTAINER");

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotContainer.selector, notContainer));
        reshufflingGateway.sendToLocalContainer(notContainer, new address[](1), new uint256[](1));
    }

    function test_RevertIf_SendToLocalContainer_NotLocalContainer() public {
        _setReshufflingMode();
        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.IncorrectContainerType.selector,
                address(containerPrincipal),
                uint8(IContainer.ContainerType.Local),
                uint8(IContainer.ContainerType.Principal)
            )
        );
        reshufflingGateway.sendToLocalContainer(address(containerPrincipal), new address[](1), new uint256[](1));
    }

    function test_RevertIf_SendToLocalContainer_TokenNotWhitelisted() public {
        _setReshufflingMode();

        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("NOT_WHITELISTED_TOKEN");

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(IReshufflingGateway.NotWhitelistedToken.selector, address(tokens[0])));
        reshufflingGateway.sendToLocalContainer(address(containerLocal), tokens, new uint256[](1));
    }

    function test_RevertIf_SendToLocalContainer_TokenNotWhitelistedOnContainer() public {
        _setReshufflingMode();

        address[] memory tokens = new address[](1);
        tokens[0] = address(notion);

        vm.mockCall(
            address(containerLocal),
            abi.encodeWithSelector(IContainer.isTokenWhitelisted.selector, address(notion)),
            abi.encode(false)
        );

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(
            abi.encodeWithSelector(IReshufflingGateway.TokenNotWhitelistedOnContainer.selector, address(notion))
        );
        reshufflingGateway.sendToLocalContainer(address(containerLocal), tokens, new uint256[](1));
    }

    function test_RevertIf_SendToLocalContainer_BalanceLessThanAmount() public {
        _setReshufflingMode();

        address[] memory tokens = new address[](1);
        tokens[0] = address(notion);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = vm.randomUint(MIN_TOKEN_AMOUNT, MAX_TOKEN_AMOUNT);
        uint256 balance = amounts[0] - 1;

        vm.mockCall(
            address(notion),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(reshufflingGateway)),
            abi.encode(balance)
        );

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotEnoughTokens.selector, address(notion), amounts[0], balance));
        reshufflingGateway.sendToLocalContainer(address(containerLocal), tokens, amounts);
    }

    function test_RevertIf_SendToLocalContainer_EmptyArray() public {
        _setReshufflingMode();

        vm.prank(roles.reshufflingManager);
        vm.expectRevert(Errors.ZeroArrayLength.selector);
        reshufflingGateway.sendToLocalContainer(address(containerLocal), new address[](0), new uint256[](0));
    }
}
