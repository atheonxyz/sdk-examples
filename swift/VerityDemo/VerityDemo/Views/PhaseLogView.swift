import SwiftUI

struct PhaseLogView: View {
    let entries: [PhaseLogEntry]
    let currentPhase: ProofPhase?

    var body: some View {
        GroupBox("Progress") {
            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: entry.phase))
                            .foregroundStyle(iconColor(for: entry.phase))
                            .font(.subheadline)
                        if let step = entry.stepName {
                            Text("\(step) — \(entry.phase.rawValue)")
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } else {
                            Text(entry.phase.rawValue)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text(formatTime(entry.duration))
                            .font(.subheadline.monospaced())
                        Text(String(format: "%.1f MB", entry.memoryAfter.processMemoryMB))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let phase = currentPhase, phase != .done {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("\(phase.rawValue)...")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func iconName(for phase: ProofPhase) -> String {
        switch phase {
        case .downloading: return "arrow.down.circle.fill"
        case .cached: return "internaldrive.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private func iconColor(for phase: ProofPhase) -> Color {
        switch phase {
        case .downloading: return .orange
        case .cached: return .blue
        default: return .green
        }
    }
}
