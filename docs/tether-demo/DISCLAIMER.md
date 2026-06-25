# Disclaimer

**This is a demo only.**

- **Not production USDT or Plasma support.** The SOHOPay production deployment (D1) is
  USDC on Base and is **untouched** by this repository.
- **Not audited for this chain.** The contracts are vendored byte-for-byte from
  [sohopay-protocol](https://github.com/sohopay/sohopay-protocol) at the commit pinned in
  [`SYNCED_FROM`](../../SYNCED_FROM); the EVM repo remains the source of truth for bytecode
  logic and invariant/unit test proof.
- **Testnet + mock token.** The default settlement asset is `MockUSDTNonStandard` with a
  permissionless mint. No real funds are involved.
- **No gasless promise.** Gas is paid in **XPL** by the executor. Plasma's USDT paymaster /
  ERC-4337 gas abstraction is explicitly out of scope — do not present settlement as gasless.
- **Demo wiring is not production wiring.** `run-plasma-demo.sh` uses a zero-renounce,
  short-timelock setup so all five acts run in one pass. A real deployment uses the full
  timelocked `Deploy.s.sol` two-leg with the Treasury Safe.

Before any real funds: dual audit, formal verification of the §8 invariants, and Gate-0
legal all still apply.
