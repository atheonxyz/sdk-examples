# Verity SDK Examples

Example apps demonstrating how to use the [Verity](https://github.com/atheonxyz/verity) zero-knowledge proof SDK.

## Swift (iOS)

A SwiftUI app that generates and verifies zero-knowledge proofs on-device using the Verity SDK. Precompiled prover/verifier schemes are downloaded on demand — not bundled in the app.

### Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 16+ device or simulator

### Setup

```bash
cd swift/VerityDemo
xcodegen generate
open VerityDemo.xcodeproj
```

Xcode will automatically fetch the Verity SPM package from the [v0.3.0 release](https://github.com/atheonxyz/verity/releases/tag/v0.3.0).

### Run

1. Select an iOS simulator or device target in Xcode.
2. Build and run (`Cmd+R`).
3. Pick a circuit from the list.
4. Tap **Download Precompiled Schemes** (one-time, cached locally).
5. Tap **Generate Proof**.

Toggle **Use Precompiled Schemes** off to compile from the circuit JSON at runtime instead (slower but requires no download).

### Hosting Precompiled Schemes

The `.pkp` (prover) and `.pkv` (verifier) files are **not** included in this repo. They are downloaded at runtime from a configurable URL.

To host them yourself:

1. Create a GitHub Release (e.g. `schemes-v0.3.0`) on this repo.
2. Upload each `.pkp` and `.pkv` file as a release asset:
   ```
   poseidon2_prover.pkp
   poseidon2_verifier.pkv
   noir_sha256_prover.pkp
   noir_sha256_verifier.pkv
   complete_age_check_prover.pkp
   complete_age_check_verifier.pkv
   t_add_dsc_720_prover.pkp
   t_add_dsc_720_verifier.pkv
   t_add_id_data_720_prover.pkp
   t_add_id_data_720_verifier.pkv
   t_add_integrity_commit_prover.pkp
   t_add_integrity_commit_verifier.pkv
   t_attest_prover.pkp
   t_attest_verifier.pkv
   ```
3. Update `SchemeDownloader.baseURL` in `Services/SchemeDownloader.swift` to match:
   ```swift
   static let baseURL = "https://github.com/{owner}/{repo}/releases/download/schemes-v0.3.0"
   ```

Pre-built scheme files can be generated with the Verity SDK's `prepare()` + `saveProver()`/`saveVerifier()` methods, or found in the main [verity](https://github.com/atheonxyz/verity) repo under `examples/ios/VerityDemo/VerityDemo/Resources/circuits/`.

### Bundled Circuits

| Circuit | Description |
|---------|-------------|
| Poseidon2 | Hash function proof — fast, small circuit |
| SHA-256 | SHA-256 hash proof — medium complexity |
| Age Check | Passport age verification — larger circuit |
| Age Check (Fragmented) | 4-step chained passport proof |

### Features

- Backend selection (ProveKit / Barretenberg)
- On-demand scheme download with local caching
- Live phase-by-phase progress logging
- Timing and memory diagnostics
- Fragmented (multi-step) proof support

## Kotlin (Android)

Coming soon.
