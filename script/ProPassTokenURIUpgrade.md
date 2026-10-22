# Soft ACK #139 Lock I — ProPass `tokenURI` upgrade

Replace the empty `tokenURI` stub with on-chain ERC-721 metadata
(`data:application/json;base64,...`). Image is the shared brand icon
`https://0xterm.xyz/logo.svg`. Optional Soft-nice `expiresAt` attribute is
included from storage.

Storage layout is unchanged (membership / `expiresAt` / price preserved across
UUPS upgrade).

## Sepolia ProPass (live)

| Field | Value |
| --- | --- |
| **proxy** (upgrade this) | `0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e` |
| prior impl (slice 1) | `0x4FB39Ce261692955DC0eFF94cba79f6e552Bf170` |
| owner | `0x333c3d8F66bD0f83022138Ed81Fc74308bF380F3` |

Syung operator broadcasts after Soft PASS + merge. Eng does not broadcast.

## Signer rule

Foundry keystore `--account` only. **Never** `PRIVATE_KEY` env inside scripts.
Bare `vm.startBroadcast()` so `--account deployer` supplies the signer.

```bash
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export PRO_PASS=0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e
# optional for large initcode:
export FOUNDRY_PROFILE=chat
```

## Dry-run

```bash
forge script script/UpgradeProPass.s.sol:UpgradeProPass \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address)" "$PRO_PASS" \
  --slow
```

Omit `--broadcast`. Confirm new implementation address and that proxy owner is
the keystore account.

## Broadcast (Syung after Soft PASS + merge)

```bash
forge script script/UpgradeProPass.s.sol:UpgradeProPass \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address)" "$PRO_PASS" \
  --broadcast --slow
```

## Sanity-check after upgrade

```bash
# pick any minted tokenId (e.g. 1)
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "tokenURI(uint256)(string)" 1

# decode: strip data:application/json;base64, then base64 -d
# expect JSON with:
#   "name":"0xterm Pro #<id>"
#   "image":"https://0xterm.xyz/logo.svg"
#   attributes expiresAt (unix)

cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "IMAGE_URI()(string)"
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "isPro(address)(bool)" 0x333c3d8F66bD0f83022138Ed81Fc74308bF380F3
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "pricePerPeriod()(uint256)"
```

Membership and price storage must match pre-upgrade values.
