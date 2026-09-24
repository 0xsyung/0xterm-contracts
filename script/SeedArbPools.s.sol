// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { IERC20 } from "@uniswap/v2-core/contracts/interfaces/IERC20.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { SimpleRouter } from "../src/SimpleRouter.sol";

/**
 * @title SeedArbPools
 * @dev Seeds Sepolia liquidity so the full arb loop (scan -> sim -> run) is real:
 *      creates + seeds the univ2-custom WETH/USDC pair (needed because the
 *      factory has no live pair yet). The univ3 WETH/USDC pool already exists
 *      on Sepolia and is seeded separately via the app's createpool/addliq.
 *
 *      The univ2-custom router is SimpleRouter (swapExactTokensForTokens +
 *      addLiquidity); the deployer must hold USDC. WETH is obtained by wrapping
 *      deployer ETH via the canonical WETH9.
 *
 * Usage (testnet only):
 *   export SEPOLIA_RPC_URL=...
 *   forge script script/SeedArbPools.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL --account <account-name> --sender <YOUR_ADDRESS>
 *   # dry-run, then re-run with --broadcast
 */
contract SeedArbPools is Script {
    // Sepolia univ2-custom (0xterm-app DEX_REGISTRY[11155111]).
    address constant V2_FACTORY = 0x26F278090C6C954c302FEfA7e60d0DD2779C1f85;
    address constant V2_ROUTER = 0x4C2c0AE850490522585a1d04Df7d00f7807750AA;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    // Seed size (reserves): ~0.05 WETH and ~200 USDC -> price 4000 USDC/WETH.
    uint256 constant WETH_AMOUNT = 0.05 ether;
    uint256 constant USDC_AMOUNT = 200e6; // 200 USDC (6 decimals)

    function run() external {
        vm.startBroadcast();

        // Wrap deployer ETH into WETH (funds the pair seed).
        (bool ok, ) = WETH.call{value: WETH_AMOUNT}("");
        require(ok, "WETH_DEPOSIT_FAILED");

        // Approve the router to move WETH + USDC.
        IERC20(WETH).approve(V2_ROUTER, WETH_AMOUNT);
        IERC20(USDC).approve(V2_ROUTER, USDC_AMOUNT);

        // Create the pair if it doesn't exist yet, then add liquidity.
        address pair = IUniswapV2Factory(V2_FACTORY).getPair(WETH, USDC);
        if (pair == address(0)) {
            pair = IUniswapV2Factory(V2_FACTORY).createPair(WETH, USDC);
            console.log("Created univ2-custom WETH/USDC pair:", pair);
        } else {
            console.log("univ2-custom WETH/USDC pair already exists:", pair);
        }

        // Generous deadline: the script's cached block.timestamp can lag the
        // block the tx actually executes against, so +1 expires mid-flight.
        SimpleRouter(V2_ROUTER).addLiquidity(WETH, USDC, WETH_AMOUNT, USDC_AMOUNT, 0, 0, msg.sender, block.timestamp + 120);

        console.log("Seeded univ2-custom WETH/USDC:");
        console.log("  WETH:", WETH_AMOUNT);
        console.log("  USDC:", USDC_AMOUNT);
        console.log("  pair:", pair);

        vm.stopBroadcast();
    }
}
