1. 相对稳定币：Anchored or Pegged (锚定或挂钩)-> $1.00
    1. chainlink Price feed.
    2. Set a function to exchange ETH&BTC -> $
2. 币的稳定机制： Algorithmic (去中心化) mint 和 burn

3. 抵押物： 采用外部抵押方式，以ETH&BTC等区块链加密货币为抵押物；

------------------------

1. What are our invariant/properties(不变量/属性)?
    stateful/stateless fuzz test

FUZZ TEST is test every situations by passing random data

1. some proper oracle use ✅
2. Write more tests 🫵
3. Smart Contract preparation


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
