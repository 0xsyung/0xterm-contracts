// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Chat} from "../src/Chat.sol";
import {ChatFactory} from "../src/ChatFactory.sol";
import {Billboard} from "../src/Billboard.sol";
import {PortfolioShare} from "../src/PortfolioShare.sol";
import {EnsRegistry} from "../src/EnsRegistry.sol";
import {ERC20Base} from "../src/ERC20Base.sol";
import {MockToken} from "../src/MockToken.sol";

/**
 * @dev Deploy-gas budget guard. Live Sepolia charges ~1,560 gas/byte of initcode
 *      (measured via eth_estimateGas — ~1.56M gas per KB, far above anvil's
 *      ~200 gas/byte model), so every byte of creation code matters. Asserting
 *      `creationCode.length` catches code-size regressions directly, without
 *      depending on gasleft()-around-cheatcode timing that Foundry distorts.
 *
 *      These guards only enforce under the optimized deploy build (the `chat`
 *      profile, which sets via_ir). Under the legacy default build Chat's
 *      creation code is ~15.6KB — far above the budget — so the suite skips
 *      there rather than failing the default `forge test`. CI runs both
 *      profiles (see .github/workflows/test.yml).
 *
 *      Budgets are byte-length caps derived from the measured viaIR build with
 *      ~12% headroom. NOTE: these guard SIZE, not a live-deploy guarantee —
 *      deploy scripts must still dry-run against a live RPC (script/*Deploy.md).
 */
contract DeployGasBudgetTest is Test {
    // viaIR builds are ~7.3KB (Chat) down to ~1.5KB (ChatFactory). The legacy
    // default build is ~15.6KB for Chat — a clean discriminator for via_ir.
    uint256 constant VIAIR_DETECT = 10_000;

    // viaIR build measured sizes + ~12% headroom (bytes of creation code).
    uint256 constant CHAT_BUDGET = 8_200; // 7312B measured
    uint256 constant DEFAULT_BUDGET = 5_200; // 4507B largest non-Chat target

    modifier skipUnlessViaIR() {
        if (type(Chat).creationCode.length > VIAIR_DETECT) vm.skip(true, "not viaIR build (default profile)");
        _;
    }

    function test_Chat_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(Chat).creationCode.length;
        emit log_named_uint("chat_creation_code_bytes", len);
        assertLt(len, CHAT_BUDGET, "Chat creation code above budget");
    }

    function test_ChatFactory_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(ChatFactory).creationCode.length;
        emit log_named_uint("chatfactory_creation_code_bytes", len);
        assertLt(len, DEFAULT_BUDGET, "ChatFactory creation code above budget");
    }

    function test_Billboard_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(Billboard).creationCode.length;
        emit log_named_uint("billboard_creation_code_bytes", len);
        assertLt(len, DEFAULT_BUDGET, "Billboard creation code above budget");
    }

    function test_PortfolioShare_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(PortfolioShare).creationCode.length;
        emit log_named_uint("portfolioshare_creation_code_bytes", len);
        assertLt(len, DEFAULT_BUDGET, "PortfolioShare creation code above budget");
    }

    function test_EnsRegistry_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(EnsRegistry).creationCode.length;
        emit log_named_uint("ensregistry_creation_code_bytes", len);
        assertLt(len, DEFAULT_BUDGET, "EnsRegistry creation code above budget");
    }

    function test_ERC20Base_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(ERC20Base).creationCode.length;
        emit log_named_uint("erc20base_creation_code_bytes", len);
        assertLt(len, DEFAULT_BUDGET, "ERC20Base creation code above budget");
    }

    function test_MockToken_CreationCode_UnderBudget() public skipUnlessViaIR {
        uint256 len = type(MockToken).creationCode.length;
        emit log_named_uint("mocktoken_creation_code_bytes", len);
        assertLt(len, DEFAULT_BUDGET, "MockToken creation code above budget");
    }
}
