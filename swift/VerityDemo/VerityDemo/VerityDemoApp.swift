import SwiftUI

@main
struct VerityDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { SchemeDownloader.shared.preloadAll() }
        }
    }
}
