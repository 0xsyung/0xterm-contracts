# Soft ACK #139 slice 2 — onlyPro upgrades

Wire the live Sepolia **ProPass proxy** into own-product mutatives via
immutable `proPass` on each UUPS implementation (and factories). Clones of a
shared Chat/GroupChat implementation inherit the same gate from bytecode.

## Sepolia ProPass (slice 1 broadcast)

| Field | Value |
| --- | --- |
| **proxy** (use this) | `0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e` |
| impl | `0x4FB39Ce261692955DC0eFF94cba79f6e552Bf170` |
| owner | `0x333c3d8F66bD0f83022138Ed81Fc74308bF380F3` |
| price / period | `0.01 ether` / `2592000` s |

**Will / WillFactory / WillVault:** no ProPass gate in v1 (Soft ACK #139 lock B / #247 lock 10).

**SimpleRouter / mocks / tokens / WETH / Counter:** left ungated (external DEX
paths use app B1 preflight; Soft ACK lock C).

## Signer rule

Foundry keystore `--account` only. **Never** `PRIVATE_KEY` env inside scripts.
Bare `vm.startBroadcast()` so `--account deployer` supplies the signer.

```bash
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export PRO_PASS=0x509473decdd7F9Aa84fbd884cB05D5Ebd35cFC6e
# optional for large initcode:
export FOUNDRY_PROFILE=chat
```

## Upgrade existing UUPS proxies

```bash
# Chat
forge script script/UpgradeChat.s.sol:UpgradeChat \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address,address)" <CHAT_PROXY> "$PRO_PASS" \
  --broadcast --slow

# Billboard
forge script script/UpgradeBillboard.s.sol:UpgradeBillboard \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address,address)" <BILLBOARD_PROXY> "$PRO_PASS" \
  --broadcast --slow

# ENS
forge script script/UpgradeENS.s.sol:UpgradeENS \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address,address)" <ENS_PROXY> "$PRO_PASS" \
  --broadcast --slow

# PortfolioShare
forge script script/UpgradePortfolioShare.s.sol:UpgradePortfolioShare \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address,address)" <SHARE_PROXY> "$PRO_PASS" \
  --broadcast --slow
```

Dry-run: omit `--broadcast`.

## Redeploy factories (new clones gated)

EIP-1167 clones pin the implementation address at create time. Updating
`factory.setImplementation(new Chat(proPass))` gates **future** clones only.
Existing clones keep their prior bytecode (grandfathered). Prefer redeploying
the factory + shared impl for a clean Sepolia cutover:

```bash
forge script script/DeployChatFactory.s.sol:DeployChatFactory \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address)" "$PRO_PASS" --broadcast --slow

forge script script/DeployGroupChat.s.sol:DeployGroupChat \
  --rpc-url "$SEPOLIA_RPC_URL" --account deployer \
  --sender "$(cast wallet address deployer)" \
  --sig "run(address)" "$PRO_PASS" --broadcast --slow
```

Wire new factory / impl addresses into the app after broadcast.

## Fresh deploys (same ProPass arg)

`DeployChat` / `DeployBillboard` / `DeployENS` / `DeployPortfolioShare` all take
`--sig "run(address)" "$PRO_PASS"`.
