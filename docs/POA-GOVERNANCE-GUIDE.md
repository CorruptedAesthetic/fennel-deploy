# Proof of Authority Governance Guide

## Overview

This blockchain uses a **Proof of Authority (PoA)** consensus model with sudo-controlled validator management. This is ideal for:
- Enterprise/consortium blockchains
- Private networks with known participants
- Gradual decentralization strategies
- Compliance-focused deployments

## Current Governance Model

### 1. Sudo Authority
- **Single privileged account** controls validator set
- Uses custom `pallet-validator-manager` for operations
- No multisig required initially
- Clean, simple governance for launch

### 2. Validator Management Operations

```rust
// Add new validators (sudo only)
validator_manager.registerValidators([
    "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY",
    "5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty"
])

// Remove a validator (sudo only)  
validator_manager.removeValidator(
    "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY"
)
```

### 3. Session-Based Activation
- Changes take effect after **2 sessions** (security buffer)
- Prevents immediate validator set manipulation
- Allows time for nodes to prepare for changes

## Operational Procedures

### Adding a New Validator

1. **Generate validator keys** on the new node:
   ```bash
   curl -H "Content-Type: application/json" \
        -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' \
        http://validator-node:9944
   ```

2. **Register validator** via sudo account:
   ```bash
   # Using Polkadot.js Apps or fennel-cli
   sudo.sudo(
     validatorManager.registerValidators([validator_account])
   )
   ```

3. **Wait 2 sessions** for activation (~20 minutes with 10-minute sessions)

4. **Verify activation**:
   ```bash
   curl -H "Content-Type: application/json" \
        -d '{"id":1, "jsonrpc":"2.0", "method": "staking_validators"}' \
        http://localhost:9944
   ```

### Removing a Validator

1. **Check minimum validator count**:
   - Must maintain `MinAuthorities` (typically 3-4)
   - Cannot remove if it would go below minimum

2. **Remove validator**:
   ```bash
   sudo.sudo(
     validatorManager.removeValidator(validator_account)
   )
   ```

3. **Graceful shutdown** after 2 sessions

## Future Governance Evolution

### Phase 1: Current PoA (Launch)
- ✅ Single sudo authority
- ✅ Direct validator management
- ✅ Quick decision making
- ✅ Ideal for initial deployment

### Phase 2: Council Introduction (3-6 months)
```rust
// Add council pallet to runtime
pallet_collective::{Instance1} = 10,
pallet_membership::{Instance1} = 11,

// Transition validator management to council
type PrivilegedOrigin = EnsureRootOrHalfCouncil;
```

### Phase 3: Multisig Treasury (6-12 months)
```rust
// Add treasury and multisig
pallet_treasury = 12,
pallet_multisig = 13,

// Sudo transfers to multisig
sudo.sudo(
  system.setCode(new_runtime_with_multisig)
)
```

### Phase 4: Full Decentralization (12+ months)
```rust
// Remove sudo entirely
pallet_sudo = None,

// Validator elections
pallet_staking = 14,
pallet_election_provider_multi_phase = 15,
```

## Runtime Upgrade Path

### 1. Prepare New Runtime
```rust
// runtime/src/lib.rs
#[cfg(feature = "phase-2-governance")]
impl pallet_collective::Config<Instance1> for Runtime {
    // Council configuration
}

// Keep validator-manager but change origin
impl pallet_validator_manager::Config for Runtime {
    #[cfg(feature = "phase-1-governance")]
    type PrivilegedOrigin = EnsureSudo;
    
    #[cfg(feature = "phase-2-governance")]
    type PrivilegedOrigin = EnsureRootOrHalfCouncil;
}
```

### 2. Build & Test New Runtime
```bash
# Build with new governance
cargo build --release --features phase-2-governance

# Test in local network first
./target/release/fennel-node --dev --tmp
```

### 3. Execute Runtime Upgrade
```javascript
// Using Polkadot.js
const code = fs.readFileSync('./runtime.wasm');
api.tx.sudo.sudo(
  api.tx.system.setCode(code)
).signAndSend(sudoAccount);
```

### 4. Verify Upgrade
```bash
# Check runtime version increased
curl -H "Content-Type: application/json" \
     -d '{"id":1, "jsonrpc":"2.0", "method": "state_getRuntimeVersion"}' \
     http://localhost:9944
```

## Security Considerations

### Sudo Key Protection
1. **Hardware wallet** recommended for sudo account
2. **Cold storage** between operations
3. **Audit log** all sudo transactions
4. **Backup procedures** for key recovery

### Validator Vetting Process
1. **KYC/KYB** for validator operators
2. **Technical requirements** verification
3. **SLA agreements** for uptime
4. **Security audit** of validator infrastructure

### Emergency Procedures
1. **Validator misbehavior**: Immediate removal via sudo
2. **Network attack**: Pause block production if needed
3. **Key compromise**: Runtime upgrade to rotate sudo
4. **Fork recovery**: Coordinate validator rollback

## Monitoring & Compliance

### Key Metrics
- Validator uptime and performance
- Block production rate
- Network latency between validators
- Sudo transaction history

### Compliance Records
- All validator additions/removals
- Sudo action justifications
- Network governance decisions
- Security incident reports

## Advantages of This Approach

1. **Simple Launch**: No complex multisig coordination
2. **Fast Iteration**: Quick validator changes when needed
3. **Clear Authority**: Single point of responsibility
4. **Gradual Decentralization**: Evolve governance over time
5. **Enterprise Ready**: Meets compliance requirements

## Next Steps

1. **Document sudo procedures** in operational runbook
2. **Set up monitoring** for validator operations
3. **Plan governance roadmap** with timeline
4. **Prepare runtime upgrade** procedures
5. **Train operations team** on validator management

---

This PoA model with validator-manager pallet provides the perfect balance of control and flexibility for launching your blockchain network! 