// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Chat} from "../src/Chat.sol";
import {ChatFactory} from "../src/ChatFactory.sol";
import {Billboard} from "../src/Billboard.sol";
import {PortfolioShare} from "../src/PortfolioShare.sol";
import {EnsRegistry} from "../src/EnsRegistry.sol";
import {ERC20Base} from "../src/ERC20Base.sol";
import {MockToken} from "../src/MockToken.sol";

/**
 * @dev Deploy-gas budget guard. Live Sepolia charges ~1,560 gas/byte of
 *      initcode (measured via eth_estimateGas, far above anvil's model), so
 *      every byte of creation bytecode matters. These asserts keep creation
 *      gas from silently growing past the tx budget as the suite evolves.
 *
 *      Budgets are deliberately generous (anvil creation gas is ~10x LOWER than
 *      live Sepolia): they exist to catch REGRESSIONS in code size, not to
 *      guarantee a live deploy fits. Deploy scripts still dry-run against a
 *      live RPC before broadcast.
 */
contract DeployGasBudgetTest is Test {
    // Budgets set from measured anvil-local creation gas (viaIR build) with
    // ~15% headroom. anvil's code-deposit (~200 gas/byte) is ~10x LOWER than live
    // Sepolia (~1,560 gas/byte), so these only catch code-size regressions.
    uint256 constant CHAT_BUDGET = 1_700_000;
    uint256 constant DEFAULT_BUDGET = 1_100_000;

    function test_Chat_UupsCreationGas_UnderBudget() public {
        uint256 g0 = gasleft();
        Chat impl = new Chat();
        uint256 gas = g0 - gasleft();
        impl; // silence
        emit log_named_uint("chat_impl_creation_gas", gas);
        assertLt(gas, CHAT_BUDGET, "Chat impl creation gas above budget");
    }

    function test_ChatFactory_CreationGas_UnderBudget() public {
        Chat impl = new Chat();
        uint256 g0 = gasleft();
        ChatFactory f = new ChatFactory(address(impl));
        uint256 gas = g0 - gasleft();
        f; // silence
        emit log_named_uint("chatfactory_creation_gas", gas);
        assertLt(gas, DEFAULT_BUDGET, "ChatFactory creation gas above budget");
    }

    function test_Billboard_UupsCreationGas_UnderBudget() public {
        uint256 g0 = gasleft();
        Billboard impl = new Billboard();
        uint256 gas = g0 - gasleft();
        impl; // silence
        emit log_named_uint("billboard_impl_creation_gas", gas);
        assertLt(gas, DEFAULT_BUDGET, "Billboard impl creation gas above budget");
    }

    function test_PortfolioShare_UupsCreationGas_UnderBudget() public {
        uint256 g0 = gasleft();
        PortfolioShare impl = new PortfolioShare();
        uint256 gas = g0 - gasleft();
        impl; // silence
        emit log_named_uint("portfolioshare_impl_creation_gas", gas);
        assertLt(gas, DEFAULT_BUDGET, "PortfolioShare impl creation gas above budget");
    }

    function test_EnsRegistry_UupsCreationGas_UnderBudget() public {
        uint256 g0 = gasleft();
        EnsRegistry impl = new EnsRegistry();
        uint256 gas = g0 - gasleft();
        impl; // silence
        emit log_named_uint("ensregistry_impl_creation_gas", gas);
        assertLt(gas, DEFAULT_BUDGET, "EnsRegistry impl creation gas above budget");
    }

    function test_ERC20Base_CreationGas_UnderBudget() public {
        uint256 g0 = gasleft();
        ERC20Base impl = new ERC20Base();
        uint256 gas = g0 - gasleft();
        impl; // silence
        emit log_named_uint("erc20base_creation_gas", gas);
        assertLt(gas, DEFAULT_BUDGET, "ERC20Base creation gas above budget");
    }

    function test_MockToken_CreationGas_UnderBudget() public {
        uint256 g0 = gasleft();
        MockToken t = new MockToken("Mock", "MCK", 18, 1_000_000);
        uint256 gas = g0 - gasleft();
        t; // silence
        emit log_named_uint("mocktoken_creation_gas", gas);
        assertLt(gas, DEFAULT_BUDGET, "MockToken creation gas above budget");
    }
}
