import SwiftUI

@main
struct ChessSenseApp: App {
    init() {
        // The engine lives in this process, so it is registered before any view asks for a
        // move. Booting Stockfish is lazy: the first analysis starts it.
        EngineRegistry.registerLocal(LocalStockfishBackend.shared)
        // Pay Stockfish's start-up before the first screenshot, not after it.
        Task.detached(priority: .utility) { LocalStockfishBackend.shared.warmUp() }
    }

    var body: some Scene {
        WindowGroup {
            // Launched with -chesssense-studio YES (Xcode scheme arg or simctl) to open the
            // Island design studio directly.
            if UserDefaults.standard.bool(forKey: "chesssense-engine") {
                NavigationStack { EngineProbeView() }
            } else if UserDefaults.standard.bool(forKey: "chesssense-studio")
                || CommandLine.arguments.contains("-chesssense-studio") {
                NavigationStack { DesignStudioView() }
            } else {
                ContentView()
            }
        }
    }
}
