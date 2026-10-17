# Will deploy

```bash
forge script script/DeployWill.s.sol:DeployWill --rpc-url $RPC --broadcast
```

Then set in `0xterm-app` `src/components/terminal/constants.ts`:

- `WILL_FACTORY[chainId]` (implementation is readable via `factory.implementation()`)

Testnets only (Sepolia primary + Base/Arb/OP Sepolia). Soft ACK #26.
No mainnet until independent audit + dedicated enable-gate PR.
