# GroupChat deploy

```bash
forge script script/DeployGroupChat.s.sol:DeployGroupChat --rpc-url $RPC --broadcast
```

Then set in `0xterm-app` `src/components/terminal/constants.ts`:

- `GROUP_CHAT_IMPLEMENTATION[chainId]`
- `GROUP_CHAT_FACTORY[chainId]`

Testnets only. Soft ACK #77.
