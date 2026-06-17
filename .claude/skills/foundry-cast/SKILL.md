---
name: foundry-cast
description: Use Foundry's `cast` CLI to read chain state, encode/decode calldata, query logs, and inspect contracts — without touching keys or broadcasting. Use when the agent needs to inspect a deployed contract, decode a transaction, look up a function selector, fetch storage, or simulate a call. Read-only by default; no MCP server required.
---

# Cast — Foundry's Chain CLI

`cast` is the read-side counterpart to `forge`. Every chain operation an agent might want from an MCP server is already a `cast` subcommand. No server, no daemon, no shebang bugs — just the binary that ships with Foundry.

Full reference: https://getfoundry.sh/cast

## When to use this skill

- Inspecting a deployed contract (bytecode, storage, ABI)
- Decoding a transaction's calldata or revert reason
- Looking up a 4-byte selector or event signature
- Fetching balance, nonce, code at an address
- Reading state via `eth_call` without writing a Forge test
- Resolving ENS names
- Encoding calldata for a script

## Setup

`cast` needs an RPC. Either pass `--rpc-url` per command or set `ETH_RPC_URL`:

```bash
export ETH_RPC_URL=https://eth.blockscout.com/api/eth-rpc   # free, no key
# or
export ETH_RPC_URL=$RPC_MAINNET                              # from .env
```

Blockscout's public RPC is the simplest no-key fallback for read-only ops.

## Read-only cheat sheet

### Account state

```bash
cast balance vitalik.eth                                 # ETH balance (wei)
cast balance vitalik.eth --ether                         # in ETH
cast nonce 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045    # tx count
cast code 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48     # runtime bytecode
cast codesize 0xa0b8...eb48
cast storage 0xa0b8...eb48 0                             # slot 0
cast proof 0xa0b8...eb48 0                               # merkle proof for slot
```

### Block / chain

```bash
cast block-number
cast block latest
cast gas-price
cast chain-id
cast base-fee
cast age <block>                                         # human time
cast find-block <timestamp>                              # block at unix time
```

### Transactions

```bash
cast tx <hash>                                           # tx envelope
cast receipt <hash>                                      # receipt + logs
cast run <hash>                                          # re-execute & trace
cast trace <hash>                                        # full call trace
cast decode-transaction <raw-hex>
cast 4byte-calldata 0xa9059cbb...                        # match selector → sig
```

### Contract reads (eth_call)

```bash
# balanceOf(address)
cast call 0xa0b8...eb48 "balanceOf(address)(uint256)" vitalik.eth

# totalSupply()
cast call 0xa0b8...eb48 "totalSupply()(uint256)"

# ERC20 helpers (built-in)
cast erc20-token name 0xa0b8...eb48
cast erc20-token symbol 0xa0b8...eb48
cast erc20-token decimals 0xa0b8...eb48
cast erc20-token total-supply 0xa0b8...eb48
cast erc20-token balance 0xa0b8...eb48 vitalik.eth
```

### Logs

```bash
cast logs --from-block 20000000 --to-block latest \
  --address 0xa0b8...eb48 \
  'Transfer(address,address,uint256)'
```

### ENS

```bash
cast resolve-name vitalik.eth        # → 0xd8da...
cast lookup-address 0xd8da...        # → vitalik.eth
cast namehash vitalik.eth
```

### Encoding / decoding

```bash
cast sig "transfer(address,uint256)"             # → 0xa9059cbb
cast sig-event "Transfer(address,address,uint256)"
cast 4byte 0xa9059cbb                            # selector → signature
cast calldata "transfer(address,uint256)" 0xdead 100
cast decode-calldata "transfer(address,uint256)" 0xa9059cbb...
cast abi-encode "f(uint256,address)" 1 0xdead
cast decode-abi "f(uint256,address)" 0x...
cast decode-error 0x...                          # decode revert data
cast decode-event "Transfer(address,address,uint256)" 0x... 0x... 0x...
```

### Conversions

```bash
cast to-wei 1.5 ether
cast from-wei 1500000000000000000
cast to-hex 255              # → 0xff
cast to-dec 0xff
cast keccak "hello"
cast to-check-sum-address 0xd8da6bf26964af9d7eed9e03e53415d37aa96045
cast format-units 1234567 6  # USDC decimals
cast parse-units 1.23 6
```

### Contract inspection

```bash
cast interface 0xa0b8...eb48                     # generate Solidity interface
cast implementation 0xPROXY...                   # EIP-1967 proxy target
cast admin 0xPROXY...                            # EIP-1967 admin
cast source 0xa0b8...eb48 --etherscan-api-key $KEY   # fetch verified source
cast disassemble 0xa0b8...eb48                   # bytecode → opcodes
```

## Write operations (require a keystore — never bare keys)

```bash
cast wallet import deployer --interactive        # one-time, encrypted keystore
cast send <addr> "transfer(address,uint256)" 0xdead 100 --account deployer
cast send <addr> "deposit()" --value 1ether --account deployer
```

**Never** pass `--private-key 0x...` on the CLI. The agent has no business handling raw keys. See `CLAUDE.md` § Hard Rules.

## Patterns

### Verify INV-1 against a deployed Vault

```bash
BAL=$(cast balance 0xVAULT)
TOTAL=$(cast call 0xVAULT "totalDeposits()(uint256)")
echo "balance=$BAL totalDeposits=$TOTAL"
[ "$BAL" = "$TOTAL" ] && echo "INV-1 holds" || echo "INV-1 BROKEN"
```

### Decode an unknown revert from a failed tx

```bash
cast run <hash> --trace-printer
# or fetch revert data and:
cast decode-error 0x08c379a0...
```

### Find which function corresponds to a selector

```bash
cast 4byte 0x70a08231          # → balanceOf(address)
```

### Quick contract recon

```bash
ADDR=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
cast erc20-token name $ADDR
cast erc20-token symbol $ADDR
cast erc20-token decimals $ADDR
cast implementation $ADDR     # is it a proxy?
cast source $ADDR --etherscan-api-key $ETHERSCAN_API_KEY > UnknownContract.sol
```

## Why no MCP

`foundry-mcp@1.1.1` (npm) is missing its shebang and won't boot. No official Foundry MCP exists. Every operation it would have wrapped already exists as a `cast` subcommand — call it from the shell directly. For block-explorer-style reads (token transfers, address history, ABIs), use the Blockscout MCP server.

## See also

- `[[foundry-cheatcodes]]` — `vm.*` equivalents inside Forge tests
- Blockscout MCP — pairs well for indexed reads (token transfers, address history)
- Full cast reference: https://getfoundry.sh/reference/cast/cast
