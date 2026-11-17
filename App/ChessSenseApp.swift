import SwiftUI

@main
struct ChessSenseApp: App {
    var body: some Scene {
        WindowGroup {
            // Launched with -chesssense-studio YES (Xcode scheme arg or simctl) to open the
            // Island design studio directly.
            if UserDefaults.standard.bool(forKey: "chesssense-studio")
                || CommandLine.arguments.contains("-chesssense-studio") {
                NavigationStack { DesignStudioView() }
            } else {
                ContentView()
            }
        }
    }
}
