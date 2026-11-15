# finmath smart derivative contracts

---

## Smart Contract Specification (Solidity)

### Smart Derivative Contract (ERC-6123)

See https://eips.ethereum.org/EIPS/eip-6123

### Secure Delivery-versus-Payment (ERC-7573)

See [ERC 7573](erc-7573.md).

#### Unit Tests

Use Node.js 16 for the legacy derivative package. Install its locked dependencies and
run the tests on Hardhat's isolated local chain:

```shell
cd solidity/derivatives
npm ci --ignore-scripts
npm test
```

