import SwiftUI

@main
struct SNSEApp: App {
    init() {
        // The engine lives in this process, so it is registered before any view asks for a
        // move. Booting Stockfish is lazy: the first analysis starts it.
        EngineRegistry.registerLocal(LocalStockfishBackend.shared)
        // Pay Stockfish's start-up before the first screenshot, not after it.
        Task.detached(priority: .utility) { LocalStockfishBackend.shared.warmUp() }

#if DEBUG
        // `-snse-island coaching` puts a studio sample on the real Island for design review.
        if let raw = UserDefaults.standard.string(forKey: "snse-island"),
           let sample = DesignStudioView.Sample(rawValue: raw) {
            let state = sample.state
            Task { await LiveActivityController.preview(state) }
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            // Launched with -snse-studio YES (Xcode scheme arg or simctl) to open the
            // Island design studio directly.
            if UserDefaults.standard.bool(forKey: "snse-engine") {
                NavigationStack { EngineProbeView() }
            } else if UserDefaults.standard.bool(forKey: "snse-studio")
                || CommandLine.arguments.contains("-snse-studio") {
                NavigationStack { DesignStudioView() }
            } else {
                ContentView()
            }
        }
    }
}
