# Will deploy

Testnets only (Sepolia primary + Base/Arb/OP Sepolia). Soft ACK #26.
No mainnet until independent audit + dedicated enable-gate PR.

Use a Foundry keystore account (recommended):

```bash
forge script script/DeployWill.s.sol:DeployWill --rpc-url $RPC --account <name> --broadcast
```

Example:

```bash
forge script script/DeployWill.s.sol:DeployWill --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast
```

`DeployWill` uses bare `vm.startBroadcast()` so `--account` supplies the signer. Do not rely on `PRIVATE_KEY` env inside the script.

Then set in `0xterm-app` `src/components/terminal/constants.ts`:

- `WILL_FACTORY[chainId]` (implementation is readable via `factory.implementation()`)
