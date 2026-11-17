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
}

/// Presents ReplayKit's broadcast picker sheet, with a clear error when the extension is not
/// available instead of a tap that does nothing.
@MainActor
enum BroadcastStarter {
    static func present(from view: UIView? = nil) {
        RPBroadcastActivityViewController.load(
            withPreferredExtension: BroadcastInfo.extensionBundleIdentifier
        ) { controller, error in
            if let error {
                NSLog("[chess-sense] broadcast picker failed: \(error.localizedDescription)")
            }
            guard let controller else { return }
            controller.delegate = Presenter.shared
            Task { @MainActor in
                topViewController()?.present(controller, animated: true)
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
