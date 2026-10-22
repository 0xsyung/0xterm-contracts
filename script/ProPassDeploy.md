# ProPass deploy

Testnets only (Sepolia primary). Soft ACK #139 slice 1 — ProPass ERC-721.
No mainnet until Soft ACK #112 / dedicated enable-gate + mainnet price.

`ProPass` is an **expirable, transferable ERC-721**. Each `purchase(periods)`
mints a **new** token with an **immutable** `expiresAt`. Holding any
non-expired pass → `isPro(account) == true`. Expired tokens stay owned
(no auto-burn).

Deploy path: UUPS implementation + `ERC1967Proxy` (same pattern as Chat /
Billboard). Callers use the **proxy** address.

## Soft ACK Sepolia defaults

| Param | Value |
| --- | --- |
| `pricePerPeriod` | **0.01 ether** |
| `periodSeconds` | **30 days** |
| `MAX_PERIODS` | **24** / tx |
| name / symbol | `0xterm Pro` / `PRO` |

Owner can later `setPricePerPeriod`. Mainnet price is **TBD** (out of scope).

## Signer rule

Use a Foundry **keystore** account. **Do not** put `PRIVATE_KEY` inside the
script (blocks `--account`). **Do not** pass `--private-key` on the CLI.

```bash
cast wallet import deployer --interactive
cast wallet list
cast wallet address deployer
```

Known account name from Will deploy docs: **`deployer`**.

## Dry-run (no broadcast)

```bash
cd /path/to/0xterm-contracts
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com

forge script script/DeployProPass.s.sol:DeployProPass \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account deployer \
  --sender "$(cast wallet address deployer)" \
  --slow
```

`DeployProPass` uses bare `vm.startBroadcast()` so `--account` supplies the
signer. Confirm predicted proxy + implementation addresses and gas.

If CREATE OOGs on live Sepolia (large UUPS initcode), retry with the
optimizer profile used for Chat:

```bash
export FOUNDRY_PROFILE=chat
```

## Broadcast

```bash
forge script script/DeployProPass.s.sol:DeployProPass \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account deployer \
  --sender "$(cast wallet address deployer)" \
  --broadcast --slow
```

Keystore password prompt → tx submitted. Save the printed **proxy** address.

## Sanity-check

```bash
PROXY=<proxy address>
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PROXY" "pricePerPeriod()(uint256)"
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PROXY" "periodSeconds()(uint64)"
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PROXY" "owner()(address)"
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PROXY" "isPro(address)(bool)" "$(cast wallet address deployer)"

# buy 1 period (0.01 ETH)
cast send --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  "$PROXY" "purchase(uint256)" 1 --value 10000000000000000

cast call --rpc-url "$SEPOLIA_RPC_URL" "$PROXY" "isPro(address)(bool)" "$(cast wallet address deployer)"
```

## Wire into the app (after Syung broadcast)

In `0xterm-app` `src/components/terminal/constants.ts`, add a per-chain
ProPass **proxy** map (same pattern as `BILLBOARD_CONTRACT` / `WILL_FACTORY`).
Placeholder until broadcast — Eng slice 3 tips app buy/status/preflight.

## Upgrade (membership preserved)

```bash
forge script script/UpgradeProPass.s.sol:UpgradeProPass \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address)" <PROXY_ADDRESS> \
  --broadcast --slow
```

Keep storage layout: only **append** new state. Do not reorder existing fields.

## Operator actions

- **Set price** (owner only):
  ```bash
  cast send --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
    "$PROXY" "setPricePerPeriod(uint256)" <new-price-wei>
  ```
- **Withdraw** ETH (owner only):
  ```bash
  cast send --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
    "$PROXY" "withdraw(address,uint256)" <to> <amount-wei>
  ```

## tokenURI metadata upgrade (Soft ACK #139 Lock I)

After Soft PASS + merge, upgrade the live Sepolia **proxy** so `tokenURI`
returns on-chain `data:application/json;base64,...` metadata with image
`https://0xterm.xyz/logo.svg`. See **`ProPassTokenURIUpgrade.md`**
(`UpgradeProPass.s.sol`, `--account` only).

