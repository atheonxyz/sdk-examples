import SwiftUI
import os
import Verity

struct ProveView: View {
    let circuit: DemoCircuit

    @State private var selectedBackend: Backend = .provekit
    @State private var usePrecompiled = true
    @State private var result: ProofResult?
    @State private var fragmentedResults: [StepResult]?
    @State private var isRunning = false
    @State private var error: String?
    @State private var runTask: Task<Void, Never>?
    @State private var currentPhase: ProofPhase?
    @State private var liveLog: [PhaseLogEntry] = []

    @State private var service = VerityService()
    @ObservedObject private var downloader = SchemeDownloader.shared
    @State private var isDownloading = false

    private var schemesDownloaded: Bool {
        downloader.isDownloaded(circuit)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Backend picker
                Picker("Backend", selection: $selectedBackend) {
                    Text("ProveKit").tag(Backend.provekit)
                    Text("Barretenberg").tag(Backend.barretenberg)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedBackend) { _ in
                    result = nil
                    error = nil
                    liveLog = []
                    currentPhase = nil
                }

                // Precompiled toggle + download
                VStack(spacing: 12) {
                    Toggle("Use Precompiled Schemes", isOn: $usePrecompiled)
                        .font(.subheadline)
                        .tint(.blue)

                    if usePrecompiled && !schemesDownloaded {
                        Button(action: downloadSchemes) {
                            HStack(spacing: 8) {
                                if isDownloading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                                Text(isDownloading ? "Downloading..." : "Download Precompiled Schemes")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(isDownloading)
                    } else if usePrecompiled && schemesDownloaded {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Schemes cached locally")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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
                .disabled(isRunning || (usePrecompiled && !schemesDownloaded))

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

                // Result (single circuit)
                if let result {
                    ResultView(result: result)
                }

                // Result (fragmented)
                if let steps = fragmentedResults {
                    FragmentedResultView(steps: steps)
                }
            }
            .padding()
        }
        .navigationTitle(circuit.name)
        .onDisappear { runTask?.cancel() }
    }

    private var buttonLabel: String {
        guard isRunning else { return "Generate Proof" }
        guard let phase = currentPhase, phase != .done else { return "Starting..." }
        return "\(phase.rawValue)..."
    }

    private func downloadSchemes() {
        isDownloading = true
        error = nil
        Task {
            do {
                try await downloader.download(circuit)
            } catch {
                self.error = error.localizedDescription
            }
            isDownloading = false
        }
    }

    private func run() {
        isRunning = true
        error = nil
        result = nil
        fragmentedResults = nil
        liveLog = []
        currentPhase = nil

        runTask = Task {
            do {
                if circuit.isFragmented {
                    let (steps, _, _, _) = try await service.generateAndVerifyFragmented(
                        circuit: circuit,
                        backend: selectedBackend,
                        usePrecompiled: usePrecompiled,
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
                } else {
                    let r = try await service.generateAndVerify(
                        circuit: circuit,
                        backend: selectedBackend,
                        usePrecompiled: usePrecompiled,
                        onPhase: { phase in
                            Task { @MainActor in currentPhase = phase }
                        },
                        onPhaseComplete: { entry in
                            Task { @MainActor in liveLog.append(entry) }
                        }
                    )
                    await MainActor.run {
                        result = r
                        isRunning = false
                    }
                }
            } catch {
                os_log("[VerityDemo] ERROR: \(error)")
                if let lastMsg = try? Verity.lastErrorMessage(for: selectedBackend) {
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
        let msg = error.localizedDescription
        if msg.contains("memory") || msg.contains("alloc") {
            return "Out of memory — try a smaller circuit or configure memory limits with Verity.configureMemory()."
        }
        if msg.contains("not found") || msg.contains("resource") {
            return "Circuit file not found in bundle. Ensure all circuit assets are included."
        }
        return msg
    }
}
