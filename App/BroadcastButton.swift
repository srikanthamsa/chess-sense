import ReplayKit
import SwiftUI
import UIKit

/// Starts a ReplayKit broadcast.
///
/// `RPSystemBroadcastPickerView` is the documented control, but it renders as a small glyph
/// that only responds to taps on the glyph itself — which is why tapping the row looked dead
/// and no sheet appeared. This type keeps the picker for its appearance and presents
/// `RPBroadcastActivityViewController` directly from a tap anywhere on the row.
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 54, height: 54)
        )
        picker.preferredExtension = BroadcastInfo.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.isUserInteractionEnabled = false   // the row around it handles the tap
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

enum BroadcastInfo {
    static let extensionBundleIdentifier = "ai.chesssense.app.broadcast"

    /// What is actually embedded in this build. A broadcast extension that failed to copy
    /// cannot be started, so the app says so instead of leaving a dead button.
    static var embeddedExtensions: [(id: String, name: String)] {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: plugins, includingPropertiesForKeys: nil)
        else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "appex",
                  let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier
            else { return nil }
            return (id, bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? id)
        }
    }

    static var diagnostics: String {
        let embedded = embeddedExtensions
        guard !embedded.isEmpty else { return "no embedded extensions" }
        return embedded.map(\.id).joined(separator: ", ")
    }
}

/// Presents ReplayKit's broadcast picker sheet, with a clear error when the extension is not
/// available instead of a tap that does nothing.
@MainActor
enum BroadcastStarter {
    /// Called with a message when the sheet could not be shown at all.
    static var onFailure: (@MainActor (String) -> Void)?
    /// Every step of the attempt, so a silent failure can be read off the screen.
    static var onLog: (@MainActor (String) -> Void)?

    private static func log(_ message: String) {
        NSLog("[chess-sense] broadcast: \(message)")
        let line = message
        Task { @MainActor in onLog?(line) }
    }

    static func present() {
        log("embedded: " + BroadcastInfo.diagnostics)
        log("load(preferred) requested")
        RPBroadcastActivityViewController.load(
            withPreferredExtension: BroadcastInfo.extensionBundleIdentifier
        ) { controller, error in
            if let controller {
                log("preferred returned a controller")
                present(controller)
                return
            }
            let first = error?.localizedDescription ?? "no controller"
            log("preferred failed: " + first)
            // The preferred-extension load fails when iOS has not registered the extension
            // yet (a reboot is the usual cure). The generic sheet still works and shows
            // whatever the system knows about, so try it before giving up.
            log("load(generic) requested")
            RPBroadcastActivityViewController.load { fallback, secondError in
                if let fallback {
                    log("generic returned a controller")
                    present(fallback)
                    return
                }
                log("generic failed: " + (secondError?.localizedDescription ?? "no controller"))
                let message = "broadcast sheet unavailable (\(first); "
                    + "\(secondError?.localizedDescription ?? "no controller"))"
                NSLog("[chess-sense] \(message)")
                Task { @MainActor in onFailure?(message) }
            }
        }
    }

    private static func present(_ controller: RPBroadcastActivityViewController) {
        controller.delegate = Presenter.shared
        Task { @MainActor in
            guard let host = topViewController() else {
                log("no view controller to present from")
                onFailure?("no view controller to present from")
                return
            }
            log("presenting on " + String(describing: type(of: host)))
            host.present(controller, animated: true) {
                log("sheet presented")
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private final class Presenter: NSObject, RPBroadcastActivityViewControllerDelegate {
        static let shared = Presenter()

        func broadcastActivityViewController(
            _ broadcastActivityViewController: RPBroadcastActivityViewController,
            didFinishWith broadcastController: RPBroadcastController?,
            error: Error?
        ) {
            if let error {
                NSLog("[chess-sense] broadcast did not start: \(error.localizedDescription)")
            }
            broadcastActivityViewController.dismiss(animated: true)
            guard let broadcastController else { return }
            broadcastController.startBroadcast { error in
                if let error {
                    NSLog("[chess-sense] startBroadcast failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
