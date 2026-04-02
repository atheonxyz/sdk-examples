import Foundation
import os

/// Downloads and caches precompiled prover/verifier schemes from a remote URL.
@MainActor
final class SchemeDownloader: ObservableObject {

    static let shared = SchemeDownloader()

    // MARK: - Configuration

    /// Base URL where scheme files are hosted.
    /// Each file is at: {baseURL}/{filename}  (e.g. poseidon2_prover.pkp)
    ///
    /// Upload .pkp/.pkv files as GitHub Release assets, then set this to:
    ///   https://github.com/{owner}/{repo}/releases/download/{tag}
    static let baseURL = "https://github.com/atheonxyz/sdk-examples/releases/download/schemes-v0.3.0"

    // MARK: - Published State

    @Published private(set) var downloadedCircuits: Set<String> = []
    @Published private(set) var activeDownloads: Set<String> = []

    private let cacheDir: URL

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VeritySchemes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheDir = dir
        refreshState()
    }

    // MARK: - Public API

    /// Whether all scheme files for this circuit are cached locally.
    func isDownloaded(_ circuit: DemoCircuit) -> Bool {
        downloadedCircuits.contains(circuit.filePrefix)
    }

    /// Local path to a cached prover scheme, or nil if not downloaded.
    func proverPath(for prefix: String) -> String? {
        let path = cacheDir.appendingPathComponent("\(prefix)_prover.pkp").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Local path to a cached verifier scheme, or nil if not downloaded.
    func verifierPath(for prefix: String) -> String? {
        let path = cacheDir.appendingPathComponent("\(prefix)_verifier.pkv").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Download all scheme files for a circuit.
    func download(_ circuit: DemoCircuit) async throws {
        let prefix = circuit.filePrefix
        activeDownloads.insert(prefix)
        defer { activeDownloads.remove(prefix); refreshState() }

        let filenames = schemeFilenames(for: circuit)

        for filename in filenames {
            guard let remoteURL = URL(string: "\(Self.baseURL)/\(filename)") else {
                throw SchemeDownloadError.httpError(0, filename)
            }
            let localURL = cacheDir.appendingPathComponent(filename)

            // Skip if already cached
            if FileManager.default.fileExists(atPath: localURL.path) { continue }

            os_log("[SchemeDownloader] Downloading %{public}@", filename)
            let (tempFile, response) = try await URLSession.shared.download(from: remoteURL)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw SchemeDownloadError.httpError(code, filename)
            }

            try FileManager.default.moveItem(at: tempFile, to: localURL)
        }

        os_log("[SchemeDownloader] All schemes cached for %{public}@", prefix)
    }

    /// Remove cached schemes for a circuit.
    func remove(_ circuit: DemoCircuit) {
        for filename in schemeFilenames(for: circuit) {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(filename))
        }
        refreshState()
    }

    // MARK: - Internals

    private func refreshState() {
        var downloaded = Set<String>()
        for circuit in bundledCircuits {
            let allExist = schemeFilenames(for: circuit).allSatisfy {
                FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent($0).path)
            }
            if allExist { downloaded.insert(circuit.filePrefix) }
        }
        downloadedCircuits = downloaded
    }

    private func schemeFilenames(for circuit: DemoCircuit) -> [String] {
        if let steps = circuit.steps {
            return steps.flatMap { step in
                ["\(step)_prover.pkp", "\(step)_verifier.pkv"]
            }
        }
        return ["\(circuit.filePrefix)_prover.pkp", "\(circuit.filePrefix)_verifier.pkv"]
    }
}

enum SchemeDownloadError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let file): return "Download failed for \(file) (HTTP \(code))"
        }
    }
}
