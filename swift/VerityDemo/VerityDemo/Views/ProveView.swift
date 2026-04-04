import SwiftUI
import os
import Verity

struct ProveView: View {
    let circuit: DemoCircuit

    @State private var fragmentedResults: [StepResult]?
    @State private var isRunning = false
    @State private var error: String?
    @State private var runTask: Task<Void, Never>?
    @State private var currentPhase: ProofPhase?
    @State private var liveLog: [PhaseLogEntry] = []

    @State private var service = VerityService()
    @ObservedObject private var downloader = SchemeDownloader.shared

    private var isCached: Bool { downloader.isDownloaded(circuit) }
    private var isDownloading: Bool { downloader.activeDownloads.contains(circuit.filePrefix) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Action button
                Button(action: run) {
                    HStack(spacing: 10) {
                        if isRunning {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(buttonLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                // Live progress log
                if !liveLog.isEmpty || (isRunning && currentPhase != nil) {
                    PhaseLogView(entries: liveLog, currentPhase: isRunning ? currentPhase : nil)
                }

                // Error
                if let error {
                    GroupBox {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Result
                if let steps = fragmentedResults {
                    FragmentedResultView(steps: steps)
                }
            }
            .padding()
        }
        .navigationTitle(circuit.name)
        .onDisappear {
            runTask?.cancel()
            isRunning = false
            currentPhase = nil
        }
    }

    private var buttonLabel: String {
        guard isRunning else { return "Generate Proof" }
        guard let phase = currentPhase, phase != .done else { return "Starting..." }
        return "\(phase.rawValue)..."
    }

    private func run() {
        isRunning = true
        error = nil
        fragmentedResults = nil
        liveLog = []
        currentPhase = nil

        runTask = Task {
            do {
                let (steps, _, _, _) = try await service.generateAndVerifyFragmented(
                    circuit: circuit,
                    backend: .provekit,
                    onPhase: { phase in
                        Task { @MainActor in currentPhase = phase }
                    },
                    onPhaseComplete: { entry in
                        Task { @MainActor in liveLog.append(entry) }
                    }
                )
                await MainActor.run {
                    fragmentedResults = steps
                    isRunning = false
                }
            } catch {
                os_log("[VerityDemo] ERROR: \(error)")
                if let lastMsg = try? Verity.lastErrorMessage(for: .provekit) {
                    os_log("[VerityDemo] lastErrorMessage: \(lastMsg ?? "nil")")
                }
                await MainActor.run {
                    self.error = friendlyError(error)
                    isRunning = false
                }
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let ve = error as? VerityError {
            return ve.errorDescription ?? "\(ve)"
        }
        if let de = error as? SchemeDownloadError {
            return de.errorDescription ?? "\(de)"
        }
        let msg = error.localizedDescription
        if msg.contains("memory") || msg.contains("alloc") {
            return "Out of memory — try a smaller circuit."
        }
        return msg
    }
}
