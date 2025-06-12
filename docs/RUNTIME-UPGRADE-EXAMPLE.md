# Runtime Upgrade Example: Adding a New Pallet

## Scenario
Your Fennel PoA chain is running, and you want to add a new pallet without restarting the network.

## Step 1: Modify Runtime Code

```rust
// In runtime/src/lib.rs

// Add the new pallet
impl pallet_new_feature::Config for Runtime {
    type RuntimeEvent = RuntimeEvent;
    // ... config
}

// Add to construct_runtime!
construct_runtime!(
    pub enum Runtime {
        // ... existing pallets ...
        NewFeature: pallet_new_feature,  // New!
    }
);

// Increment spec_version
pub const VERSION: RuntimeVersion = RuntimeVersion {
    spec_version: 101,  // Was 100
    // ... rest stays same
};
```

## Step 2: Build New Runtime

```bash
# Build the runtime
cd fennel-solonet
cargo build --release

# Extract WASM (multiple ways):
# Option 1: Use srtool for deterministic build
# Option 2: Extract from binary
./target/release/fennel-node export-runtime > new_runtime.wasm
```

## Step 3: Submit Upgrade (No Chain Spec Changes!)

```javascript
// Using Polkadot.js
const wasm = fs.readFileSync('new_runtime.wasm');

// Via sudo - your PoA approach
const upgrade = api.tx.system.setCode(wasm);
await api.tx.sudo.sudo(upgrade).signAndSend(sudoAccount);

// Wait for next block...
// New pallet is now live!
```

## What Happens:
1. **Validators continue producing blocks** (no restart)
2. **All state is preserved** (accounts, balances, validator set)
3. **New pallet is available** immediately after upgrade
4. **Chain spec remains unchanged** (still using original genesis)

## What You DON'T Need:
- ❌ New chain spec
- ❌ Node restarts
- ❌ Re-sync from genesis
- ❌ New validator keys
- ❌ Network disruption

## Key Point for PoA:
Your validator-manager pallet **survives all runtime upgrades**. You can:
- Add new pallets
- Modify existing logic
- Fix bugs
- Add features

All while maintaining your PoA governance model with sudo control! 