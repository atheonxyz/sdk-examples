import SwiftUI
import Verity

struct ContentView: View {
    @ObservedObject private var downloader = SchemeDownloader.shared
    @State private var showBanner = false

    private var allDownloaded: Bool {
        bundledCircuits.allSatisfy { downloader.isDownloaded($0) }
    }

    var body: some View {
        NavigationStack {
            CircuitListView()
                .navigationTitle("Verity Demo")
                .overlay(alignment: .bottom) {
                    if showBanner {
                        Text("Artifacts downloaded in background")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.green.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: showBanner)
                .onChange(of: allDownloaded) { done in
                    if done {
                        showBanner = true
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            showBanner = false
                        }
                    }
                }
        }
    }
}
