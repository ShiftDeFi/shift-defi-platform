// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Base} from "test/Base.t.sol";
import {MockStrategyContainer} from "test/mocks/MockStrategyContainer.sol";
import {MockStrategyInterfaceBased} from "test/mocks/MockStrategyInterfaceBased.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";

contract StrategyContainerBaseTest is Base {
    uint256 internal constant MAX_STRATEGIES = 255;
    uint256 internal constant MIN_AMOUNT = 1e18;
    uint256 internal constant MAX_AMOUNT = 1000e18;

    bytes32 internal constant STRATEGY_UNRESOLVED_NAV_BITMASK_STORAGE_SLOT = bytes32(uint256(62));

    MockStrategyContainer internal strategyContainer;
    ISwapRouter internal swapRouter;

    function setUp() public virtual override {
        super.setUp();

        swapRouter = _deployMockSwapRouter();
        strategyContainer = _deployMockStrategyContainer();

        vm.prank(roles.reshufflingExecutor);
        strategyContainer.disableReshufflingMode();

        vm.prank(roles.strategyManager);
        strategyContainer.setTreasury(treasury);
    }

    function _createAndAddStrategyWithTokens(
        uint256 inputTokenCount,
        uint256 outputTokenCount,
        bool isNotionArray
    ) internal returns (MockStrategyInterfaceBased, address[] memory, address[] memory) {
        MockStrategyInterfaceBased strategy = new MockStrategyInterfaceBased(address(strategyContainer));
        address[] memory _strategyInputTokens;
        address[] memory _strategyOutputTokens;
        if (isNotionArray) {
            _strategyInputTokens = _createTokensArray(address(notion));
            _strategyOutputTokens = _createTokensArray(address(notion));
        } else {
            _strategyInputTokens = _createRandomTokensArray(inputTokenCount);
            _strategyOutputTokens = _createRandomTokensArray(outputTokenCount);
        }
        _whitelistTokensIfNeeded(address(strategyContainer), _strategyInputTokens);
        _whitelistTokensIfNeeded(address(strategyContainer), _strategyOutputTokens);
        vm.prank(roles.strategyManager);
        strategyContainer.addStrategy(address(strategy), _strategyInputTokens, _strategyOutputTokens);
        return (strategy, _strategyInputTokens, _strategyOutputTokens);
    }

    function _addStrategyWithTokens(
        address strategy,
        address[] memory inputTokens,
        address[] memory outputTokens
    ) internal {
        vm.prank(roles.strategyManager);
        strategyContainer.addStrategy(strategy, inputTokens, outputTokens);
    }

    function _craftTokenAmountsOnStrategyContainer(address strategy) internal returns (uint256[] memory) {
        address[] memory tokens = MockStrategyInterfaceBased(strategy).getInputTokens();
        uint256[] memory amounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = vm.randomUint(MIN_AMOUNT, MAX_AMOUNT);
            MockERC20(tokens[i]).mint(address(strategyContainer), amounts[i]);
            MockERC20(tokens[i]).approve(strategy, amounts[i]);
        }
        return amounts;
    }

    function _getStrategyUnresolvedNavBitmask() internal view returns (uint256) {
        return uint256(vm.load(address(strategyContainer), STRATEGY_UNRESOLVED_NAV_BITMASK_STORAGE_SLOT));
    }

    function _isStrategyNavUnresolved(address _strategy) internal view returns (bool) {
        address[] memory strategies = strategyContainer.getStrategies();
        uint256 strategyIndex = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                strategyIndex = i;
                break;
            }
        }
        uint256 strategyNavUnresolvedBitmask = _getStrategyUnresolvedNavBitmask();
        uint256 mask = 1 << strategyIndex;
        return strategyNavUnresolvedBitmask & mask != 0;
    }
}
