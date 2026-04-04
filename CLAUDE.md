# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Verity SDK Examples — demo apps showing on-device zero-knowledge proof generation and verification using the [Verity SDK](https://github.com/atheonxyz/verity). Currently contains a Swift/iOS app (`swift/VerityDemo`); Kotlin/Android is planned but not yet implemented.

## Build & Development Commands

All commands assume you're in the repo root. The `script.sh` wrapper automates common tasks:

```bash
# Generate Xcode project from project.yml (requires xcodegen)
./script.sh generate

# Build for iOS Simulator
./script.sh build

# Resolve Swift Package Manager dependencies
./script.sh resolve

# Launch on iPhone 16 simulator
./script.sh run

# Full rebuild from scratch (clean → generate → build → run)
./script.sh full

# Clear downloaded scheme cache
./script.sh clear-cache

# Nuke DerivedData, SPM cache, uninstall app from simulator
./script.sh clean
```

Manual Xcode workflow:
```bash
cd swift/VerityDemo
xcodegen generate
open VerityDemo.xcodeproj
```

There are no unit tests or CI/CD pipelines in this repository.

## Architecture

### Swift App (`swift/VerityDemo/VerityDemo/`)

**Services layer** (concurrency-safe):
- `VerityService` — an **`actor`** that orchestrates the fragmented prove/verify pipeline (`generateAndVerifyFragmented`). Each step in a circuit is loaded, proved, and verified sequentially with per-step metrics. Uses `@Sendable` callbacks for real-time phase and timing notifications.
- `SchemeDownloader` — a **`@MainActor` ObservableObject** that downloads and caches precompiled `.pkp`/`.pkv` scheme files to `~/Library/Caches/VeritySchemes/`. Schemes are fetched from GCP on first use and skipped on subsequent runs.

**Proof pipeline** (per step): download all step schemes → for each step: load prover/verifier from `.pkp`/`.pkv` → load witness from TOML → prove → verify → collect timing/memory metrics.

**Models** (`ProofResult.swift`): `DemoCircuit`, `ProofPhase`, `MemorySnapshot`, `PhaseLogEntry`, `StepResult`, `ProofResult` — all `Sendable` for actor isolation.

**Views**: `CircuitListView` → `ProveView` (with live `PhaseLogView`) → `FragmentedResultView`.

### Key Dependency

Verity SDK (v0.4.0) via SPM — defined in `swift/VerityDemo/project.yml`. Source lives at `../verity` (sibling repo). Supports two backends: **ProveKit** (primary) and **Barretenberg**.

### Circuit Resources

Fragmented Age Check circuit bundled in `Resources/circuits/fragmented_age_check/` with 4 sub-circuit directories (`t_add_dsc_720`, `t_add_id_data_720`, `t_add_integrity_commit`, `t_attest`), each containing `_circuit.json` + `_Prover.toml`. Prover/verifier scheme binaries (`.pkp`/`.pkv`) are **not** bundled — they're downloaded at runtime from GCP (`gs://provekitv1/uploads/`) and excluded via `.gitignore`.

### Project Generation

Uses **XcodeGen** (`project.yml` → `.xcodeproj`). The `.xcodeproj` is gitignored; always regenerate with `xcodegen generate` or `./script.sh generate`.

## Verity SDK API Reference

The SDK source is at `../verity/sdks/swift/Sources/Verity/`. Key types used by this app:

**`Verity`** — factory class. `init(backend:)` initializes a backend. Core methods: `loadProver(from:)`, `loadVerifier(from:)`, `prove(with:witness:)`, `verify(with:proof:)`. Static helpers: `memoryStats()` returns `(ramUsed, swapUsed, peakRam)` in bytes (ProveKit only), `lastErrorMessage(for:)` retrieves the last backend error (global per-process, must read immediately after failure).

**`Backend`** — enum: `.provekit` (transparent, hash-based) or `.barretenberg` (KZG commitments).

**`Circuit`** — loaded from ACIR JSON (`Circuit.load(from:)`). **`Witness`** — loaded from TOML (`Witness.load(from:)`) or constructed from `[String: String]` dictionary / JSON.

**`ProverScheme` / `VerifierScheme`** — opaque handles loaded from `.pkp`/`.pkv` files. Thread-safe (per-instance NSLock). Auto-freed on deinit. Methods: `prove(witness:) → Proof`, `verify(proof:) → Bool`.

**`Proof`** — wraps raw bytes. Properties: `data`, `size`, `hex`, `hexPreview(maxBytes:)`.

**`VerityError`** — enum: `invalidInput`, `schemeReadError`, `proofFailed`, `serializationError`, `compilationFailed`, `unknownBackend`, `outOfMemory`, `resourceClosed`, `ffiError(code:)`.

### SDK Architecture (3 layers)

Swift SDK → C dispatcher (vtable routing by `VerityBackend` enum, `/core/dispatcher/`) → Rust FFI backends. All SDK calls go through `verity_*()` C functions; no backend-specific code leaks into the Swift layer.

### Note on SDK scope

The SDK provides single prove/verify operations. Multi-step (fragmented) proof chains are orchestrated entirely by this example app (`VerityService.generateAndVerifyFragmented`) — the SDK knows nothing about step sequencing.
