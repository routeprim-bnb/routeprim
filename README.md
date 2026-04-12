# RoutePrim

**Modular payment routing primitives for BNB Chain.**

RoutePrim composes EIP-7702 authority delegation with Permit2-style single-signature approvals into a minimal, gas-efficient primitive for crypto-native payment flows on BSC. Swap dispatch is handled by the PancakeSwap V3 SmartRouter.

---

## Why BSC

BNB Chain processes ~4M transactions per day at sub-cent fees, making it one of the highest-throughput EVM environments in production. Most of that volume is raw token transfers and DEX swaps — RoutePrim makes those flows programmable without asking users to change wallets or sign endless approvals.

- **~$0.001** average gas cost on BSC mainnet
- **EVM-compatible** — same Solidity, same tooling
- **Permit2 deployed** at canonical address on BSC
- **PancakeSwap V3** integrated for on-chain token swaps
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
        ├─► Swaps via PancakeSwap V3 exactInput along caller-specified path
        └─► Delivers output token to recipient
```

No wallet prompts for approvals. No sticky infinite allowances. One signature covers auth + transfer + routing.

---

## Contracts

```
src/
├── RoutePrim.sol               # Core router — auth, Permit2 pull, V3 swap dispatch
├── BatchRouter.sol             # Atomic multi-leg routing in a single call
├── interfaces/
│   ├── IRoutePrim.sol          # RouteParams, AuthParams, events, errors
│   ├── IBatchRouter.sol        # BatchLeg struct, batchRoute / batchRouteNative
│   ├── IPermit2.sol            # Minimal Permit2 interface
│   ├── IPancakeV3Router.sol    # PancakeSwap V3 exactInput interface
│   ├── IWBNB.sol               # WBNB deposit / withdraw
│   └── IERC20.sol              # Minimal ERC-20 (approve, transfer)
└── lib/
    ├── SignatureVerifier.sol    # EIP-712 digest + hardened ecrecover
    └── EIP7702Helper.sol       # Delegation detection for EIP-7702 EOAs
```

---

## Quickstart

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and install dependencies
git clone https://github.com/routeprim-bnb/routeprim
cd routeprim
forge install

# Run tests
forge test -vv

# Deploy to BSC testnet (chainId 97 → uses testnet router automatically)
forge script script/Deploy.s.sol \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --verify
```

---

## Integrating Permit2

RoutePrim uses Permit2's `permitTransferFrom` — users sign a structured message off-chain and never call `approve()` on-chain:

```solidity
// Encode a PancakeSwap V3 single-hop path: USDT → [0.05% fee] → WBNB
bytes memory path = abi.encodePacked(USDT, uint24(500), WBNB);

IRoutePrim.RouteParams memory params = IRoutePrim.RouteParams({
    tokenIn:      USDT,
    tokenOut:     WBNB,
    amountIn:     100e6,
    amountOutMin: 0.03e18,
    recipient:    msg.sender,
    deadline:     block.timestamp + 1 hours,
    permitSig:    permitSignature,  // Permit2 sig, signed off-chain
    swapData:     path              // V3 path bytes
});

IRoutePrim.AuthParams memory auth = IRoutePrim.AuthParams({
    signer:    userAddress,
    nonce:     freshNonce,
    deadline:  block.timestamp + 1 hours,
    signature: authSignature        // EIP-712 AuthParams sig, signed off-chain
});

routeprim.route(params, auth);
```

### Native BNB

For BNB-in swaps the path must start with the WBNB address — RoutePrim wraps internally:

```solidity
address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
bytes memory path = abi.encodePacked(WBNB, uint24(500), USDT);

routeprim.routeNative{value: 1 ether}(params, auth);
```

---

## Batch Routing

`BatchRouter` executes multiple legs atomically — the whole batch reverts if any single leg fails:

```solidity
IBatchRouter.BatchLeg[] memory legs = new IBatchRouter.BatchLeg[](2);
legs[0] = IBatchRouter.BatchLeg({route: params0, auth: auth0});
legs[1] = IBatchRouter.BatchLeg({route: params1, auth: auth1});

uint256[] memory out = batchRouter.batchRoute(legs);
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

Alternatively, use `setAuthority()` to register a persistent off-chain delegate without EIP-7702:

```solidity
routeprim.setAuthority(delegateAddress, auth);
```

---

## Deployed Addresses

| Network       | RoutePrim | BatchRouter |
|---------------|-----------|-------------|
| BSC Testnet   | —         | —           |
| BSC Mainnet   | —         | —           |

*Testnet deployment in progress.*

---

## Roadmap

- [x] EIP-7702 authority delegation
- [x] Permit2 single-signature token pull
- [x] PancakeSwap V3 swap adapter
- [x] Batch routing (atomic multi-leg)
- [ ] deBridge cross-chain routing
- [ ] Gas sponsorship via ERC-4337 paymaster
- [ ] BSC mainnet deployment + BscScan verification

---

## License

MIT
