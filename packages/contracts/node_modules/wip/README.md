# Wrapped IP 

The "Wrapped IP" refer to WETH-9 with additional features through relatively minor changes.

## Deployments
[STORY Odyssey Testnet](https://internal.storyscan.xyz/address/0xfa057f2e7515267ffab367d0a769f3fa1489b869) `0xFA057f2e7515267FFAB367D0a769F3Fa1489b869`


## Features
- Supports [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface detection.
- Supports [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) signed approvals.
- Supports [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) contract signature verification.
- Prevents from burning or sending WIP tokens to the contract.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy on Story Odyssey Testnet
Create a `.env` file with the following content:
```shell
STORY_PRIVATEKEY = <private_key of wallet address to execute command below>
```
you can also refer to `.env.example` file for reference.

```shell
export STORY_PRIVATE_KEY=<private_key>
$  forge script script/Deploy.s.sol:Deploy  --fork-url https://odyssey.storyrpc.io/ -v --broadcast --sender <wallet address>  --priority-gas-price 1 --slow --legacy --skip-simulation --verify  --verifier=blockscout --verifier-url=https://internal.storyscan.xyz/api
```
  




