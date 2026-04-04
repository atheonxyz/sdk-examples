import Foundation
import Verity
import Darwin

actor VerityService {

    typealias PhaseCallback = @Sendable (ProofPhase) -> Void
    typealias PhaseLogCallback = @Sendable (PhaseLogEntry) -> Void

    private let downloader: SchemeDownloader

    init(downloader: SchemeDownloader = .shared) {
        self.downloader = downloader
    }

    /// Notify UI of a phase change and yield so MainActor can render before heavy work starts.
    private func emitPhase(_ phase: ProofPhase, _ onPhase: PhaseCallback?) async {
        onPhase?(phase)
        await Task.yield()
    }

    func generateAndVerifyFragmented(
        circuit: DemoCircuit,
        backend: Backend,
        onPhase: PhaseCallback? = nil,
        onPhaseComplete: PhaseLogCallback? = nil
    ) async throws -> (steps: [StepResult], phases: [PhaseLogEntry], memoryBefore: MemorySnapshot, memoryAfter: MemorySnapshot) {
        let verity = try Verity(backend: backend)
        let memoryBefore = snapshot(backend: backend)
        var stepResults: [StepResult] = []
        var phases: [PhaseLogEntry] = []

        // --- Download or Cached ---
        let wasCached = await downloader.isDownloaded(circuit)
        if !wasCached {
            await emitPhase(.downloading, onPhase)
            let dlStart = CFAbsoluteTimeGetCurrent()
            try await downloader.download(circuit)
            let dlTime = CFAbsoluteTimeGetCurrent() - dlStart
            let dlEntry = PhaseLogEntry(phase: .downloading, duration: dlTime, memoryAfter: snapshot(backend: backend))
            phases.append(dlEntry)
            onPhaseComplete?(dlEntry)
        } else {
            await emitPhase(.cached, onPhase)
            let cachedEntry = PhaseLogEntry(phase: .cached, duration: 0, memoryAfter: snapshot(backend: backend))
            phases.append(cachedEntry)
            onPhaseComplete?(cachedEntry)
        }

        for step in circuit.steps {
            // --- Load ---
            await emitPhase(.loading, onPhase)
            let loadStart = CFAbsoluteTimeGetCurrent()
            guard let pkpPath = await downloader.proverPath(for: step),
                  let pkvPath = await downloader.verifierPath(for: step) else {
                throw VerityError.invalidInput("Scheme files not found for \(step)")
            }
            let prover = try verity.loadProver(from: pkpPath)
            let verifier = try verity.loadVerifier(from: pkvPath)
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
            let loadEntry = PhaseLogEntry(phase: .loading, duration: loadTime, memoryAfter: snapshot(backend: backend), stepName: step)
            phases.append(loadEntry)
            onPhaseComplete?(loadEntry)

            // --- Prove ---
            await emitPhase(.proving, onPhase)
            let inputPath = try bundlePath("\(step)_Prover", ext: "toml")
            let witness = try Witness.load(from: inputPath)
            let proveStart = CFAbsoluteTimeGetCurrent()
            let proof: Proof
            do {
                proof = try prover.prove(witness: witness)
            } catch {
                let msg = (try? Verity.lastErrorMessage(for: backend)) ?? "none"
                throw VerityError.invalidInput("Step '\(step)' prove() failed: \(error) | backend msg: \(msg)")
            }
            let proveTime = CFAbsoluteTimeGetCurrent() - proveStart
            let proveEntry = PhaseLogEntry(phase: .proving, duration: proveTime, memoryAfter: snapshot(backend: backend), stepName: step)
            phases.append(proveEntry)
            onPhaseComplete?(proveEntry)

            // --- Verify ---
            await emitPhase(.verifying, onPhase)
            let verifyStart = CFAbsoluteTimeGetCurrent()
            let isValid: Bool
            do {
                isValid = try verifier.verify(proof: proof)
            } catch {
                let msg = (try? Verity.lastErrorMessage(for: backend)) ?? "none"
                throw VerityError.invalidInput("Step '\(step)' verify() failed: \(error) | backend msg: \(msg)")
            }
            let verifyTime = CFAbsoluteTimeGetCurrent() - verifyStart
            let verifyEntry = PhaseLogEntry(phase: .verifying, duration: verifyTime, memoryAfter: snapshot(backend: backend), stepName: step)
            phases.append(verifyEntry)
            onPhaseComplete?(verifyEntry)

            stepResults.append(StepResult(
                name: step, loadTime: loadTime, proveTime: proveTime,
                verifyTime: verifyTime, isValid: isValid, proofSize: proof.size
            ))
        }

        onPhase?(.done)
        return (stepResults, phases, memoryBefore, snapshot(backend: backend))
    }

    // MARK: - Memory

    private func snapshot(backend: Backend) -> MemorySnapshot {
        var pkRAM: UInt?
        var pkSwap: UInt?
        var pkPeak: UInt?
        if backend == .provekit, let stats = try? Verity.memoryStats() {
            pkRAM = stats.ramUsed
            pkSwap = stats.swapUsed
            pkPeak = stats.peakRam
        }
        return MemorySnapshot(
            processMemoryMB: Self.processMemoryMB(),
            proveKitRAM: pkRAM,
            proveKitSwap: pkSwap,
            proveKitPeakRAM: pkPeak
        )
    }

    private static func processMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / (1024 * 1024) : 0
    }

    // MARK: - Bundle Helpers

    private func bundlePath(_ name: String, ext: String) throws -> String {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else {
            throw VerityError.invalidInput("bundled resource not found: \(name).\(ext)")
        }
        return path
    }
}
