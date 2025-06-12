# PoA Chain Spec Clarification

## Key Understanding: Validator-Manager is Already in the Runtime!

The `pallet-validator-manager` is already compiled into your fennel-node runtime. You don't need to "add" it to the chain spec. What you need is to configure the genesis state properly.

## Current State vs Required State

### Current (Dev Chain):
```rust
// Using Substrate's dev presets
.with_genesis_config_preset_name(sp_genesis_builder::DEV_RUNTIME_PRESET)
```
This gives you:
- Alice/Bob as validators
- Test sudo account
- Development settings

### Required (PoA Chain):
You need a custom genesis configuration that:
1. Sets YOUR production sudo account
2. Initializes validator-manager properly
3. Removes test accounts

## How Validator-Manager Works in Genesis

The validator-manager pallet doesn't need special genesis config because:
1. It starts with empty validator sets
2. Validators are added via sudo after chain launch
3. The session pallet uses validator-manager as its SessionManager

## Steps to Create PoA Chain Spec

### 1. Create Custom Genesis Config
```rust
// In chain_spec.rs
fn poa_genesis_config(
    sudo_account: AccountId,
    initial_validators: Vec<AccountId>, // Can be empty!
) -> serde_json::Value {
    serde_json::json!({
        "balances": {
            "balances": vec![
                (sudo_account.clone(), 1_000_000 * UNIT),
            ],
        },
        "sudo": {
            "key": sudo_account,
        },
        "session": {
            "keys": initial_validators.iter().map(|x| {
                (x.clone(), x.clone(), session_keys(x.clone()))
            }).collect::<Vec<_>>(),
        },
        "aura": {
            "authorities": vec![], // Empty - will be populated by validator-manager
        },
        "grandpa": {
            "authorities": vec![], // Empty - will be populated by validator-manager
        },
    })
}
```

### 2. Build the Chain Spec
```bash
# Generate the spec
./target/release/fennel-node build-spec \
    --disable-default-bootnode \
    --chain local > poaSpec.json

# Edit poaSpec.json to:
# 1. Change name to "Fennel PoA Network"
# 2. Change id to "fennel_poa"
# 3. Replace genesis with your custom config

# Convert to raw
./target/release/fennel-node build-spec \
    --chain=poaSpec.json \
    --raw > poaSpecRaw.json
```

### 3. Deploy with PoA Spec
```yaml
# In your Kubernetes deployment
containers:
- name: fennel-node
  command:
  - fennel-node
  - --chain=/config/poaSpecRaw.json  # Use custom spec
  - --validator
```

## Common Misconceptions

### ❌ "Need to add validator-manager to chain spec"
The pallet is already in the runtime. Chain spec just sets initial state.

### ❌ "Need to modify the runtime"
Your runtime already has validator-manager configured correctly.

### ❌ "Need complex genesis config for validator-manager"
Validator-manager works with empty initial state. Add validators post-launch.

## What Actually Happens

1. **Chain starts** with your sudo account and no validators (or initial set)
2. **Validator-manager** is active and waiting for commands
3. **You use sudo** to call `validatorManager.registerValidators()`
4. **After 2 sessions**, new validators become active
5. **Block production** switches to your PoA validators

## Testing Locally First

```bash
# 1. Create a test PoA spec
./target/release/fennel-node build-spec --chain local > testPoA.json

# 2. Edit to set your test sudo account

# 3. Convert to raw
./target/release/fennel-node build-spec --chain=testPoA.json --raw > testPoARaw.json

# 4. Run locally
./target/release/fennel-node \
    --dev \
    --chain=testPoARaw.json \
    --tmp

# 5. Connect with Polkadot.js and test validator operations
```

## Summary

You don't need to "add" validator-manager to the chain spec because:
1. It's already part of your compiled runtime
2. It's already configured as the SessionManager
3. It just needs proper genesis state (sudo account, no test validators)

The "custom chain spec" is about removing dev/test configuration and setting production values, not about adding new pallets! 