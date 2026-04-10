# RoutePrim

**Modular payment routing primitives for BNB Chain.**

RoutePrim composes EIP-7702 authority delegation with Permit2-style single-signature approvals into a minimal, gas-efficient primitive for crypto-native payment flows on BSC.

---

## Why BSC

BNB Chain processes ~4M transactions per day at sub-cent fees, making it one of the highest-throughput EVM environments in production. Most of that volume is raw token transfers and DEX swaps — RoutePrim makes those flows programmable without asking users to change wallets or sign endless approvals.

- **~$0.001** average gas cost on BSC mainnet
- **EVM-compatible** — same Solidity, same tooling
- **Permit2 deployed** at canonical address on BSC
- **EIP-7702** support incoming with BSC's next hardfork

---

## How It Works

```
User signs one AuthParams off-chain (EIP-712)
        │
        ▼
Relayer calls route() on RoutePrim
        │
        ├─► Verifies signature (or EIP-7702 delegated authority)
        ├─► Pulls funds from user via Permit2 (no pre-approval needed)
        ├─► Swaps / routes to destination token
        └─► Delivers output to recipient
```

No wallet prompts for approvals. No sticky infinite allowances. One signature covers auth + transfer + routing.

---

## Contracts

```
src/
├── RoutePrim.sol              # Core router — auth, Permit2 pull, swap dispatch
├── interfaces/
│   ├── IRoutePrim.sol         # RouteParams, AuthParams, events, errors
│   └── IPermit2.sol           # Minimal Permit2 interface
└── lib/
    ├── SignatureVerifier.sol   # EIP-712 digest + ecrecover
    └── EIP7702Helper.sol       # Delegation detection for EIP-7702 EOAs
```

---

## Quickstart

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and install
git clone https://github.com/routeprim-bnb/routeprim
cd routeprim
forge install

# Test
forge test

# Deploy to BSC testnet
forge script script/Deploy.s.sol \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## Integrating Permit2

RoutePrim uses Permit2's `permitTransferFrom` — users sign a structured message off-chain and never call `approve()` on-chain:

```solidity
IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
    tokenIn:      USDT,
    tokenOut:     WBNB,
    amountIn:     100e6,
    amountOutMin: 0.03e18,
    recipient:    msg.sender,
    deadline:     block.timestamp + 1 hours,
    permitSig:    permitSignature   // signed off-chain
});

IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
    signer:    userAddress,
    nonce:     freshNonce,
    deadline:  block.timestamp + 1 hours,
    signature: authSignature       // EIP-712 signed off-chain
});

routeprim.route(params, auth);
```

---

## EIP-7702 Authority Delegation

EIP-7702 lets an EOA temporarily designate a smart contract as its "code" — enabling batching and programmable auth without deploying a new account. RoutePrim detects delegated EOAs and accepts signatures from the delegated authority:

```
User EOA ──EIP-7702──► Delegate contract
                             │
                             └─► signs AuthParams on behalf of EOA
                                       │
                                       ▼
                               RoutePrim accepts it ✓
```

---

## Roadmap

- [ ] PancakeSwap V3 swap adapter
- [ ] deBridge cross-chain routing
- [ ] Batch routing (multiple hops in one call)
- [ ] Gas sponsorship via ERC-4337 paymaster
- [ ] BNB Chain EIP-7702 hardfork integration

---

## License

MIT
