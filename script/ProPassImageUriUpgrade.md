# Soft ACK — ProPass MetaMask `IMAGE_URI` upgrade

Point `ProPass.IMAGE_URI` at the Soft ACK Design dedicated PNG
(`https://0xterm.xyz/propass.png`) so MetaMask NFT cards render green `0x_`
hex instead of black-on-black (SVG `currentColor` on `logo.svg`).

On-chain JSON `tokenURI` shape is **unchanged** (Lock I). Only the `IMAGE_URI`
constant / implementation bytecode changes. Storage layout is unchanged
(membership / `expiresAt` / price preserved across UUPS upgrade).

Soft ACK Design: https://github.com/0xsyung/0xterm-app/issues/139#issuecomment-6357300710  
Soft ACK Eng (locks A–F): https://github.com/0xsyung/0xterm-app/issues/139#issuecomment-6357367666

**Host prerequisite:** land Soft Design asset `propass.png` on `0xterm-dot-xyz`
GH Pages so `https://0xterm.xyz/propass.png` returns 200 before Soft PASS Design
spot-check / Syung broadcast. Soft Design file lives on Designer box
`/workspace/propass.png` (also `/tmp/propass-nft/propass.png`).

## Sepolia ProPass (live)

| Field | Value |
| --- | --- |
| **proxy** (upgrade this) | `0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e` |
| prior impl (tokenURI Lock I) | see Etherscan / prior upgrade |
| owner | `0x333c3d8F66bD0f83022138Ed81Fc74308bF380F3` |

Syung operator broadcasts after Soft PASS + merge. Eng does not broadcast.

## Signer rule

Foundry keystore `--account` only. **Never** `PRIVATE_KEY` env inside scripts.
Bare `vm.startBroadcast()` so `--account deployer` supplies the signer.

```bash
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export PRO_PASS=0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e
# optional for large initcode / CREATE OOG:
export FOUNDRY_PROFILE=chat
# optional: forge script ... -g 800
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

If CREATE OOG: keep `FOUNDRY_PROFILE=chat` and/or raise gas (`-g 800`).

## Sanity-check after upgrade

```bash
# host must already serve the PNG
curl -sI https://0xterm.xyz/propass.png | head -5

cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "IMAGE_URI()(string)"
# expect: https://0xterm.xyz/propass.png

# pick any minted tokenId (e.g. 1)
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "tokenURI(uint256)(string)" 1

# decode: strip data:application/json;base64, then base64 -d
# expect JSON with:
#   "name":"0xterm Pro #<id>"
#   "image":"https://0xterm.xyz/propass.png"
#   attributes expiresAt (unix)

cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "isPro(address)(bool)" 0x333c3d8F66bD0f83022138Ed81Fc74308bF380F3
cast call --rpc-url "$SEPOLIA_RPC_URL" "$PRO_PASS" \
  "pricePerPeriod()(uint256)"
```

Membership and price storage must match pre-upgrade values. Soft PASS Design
spot-check: MetaMask NFT card shows green `0x_` hex (not black).
