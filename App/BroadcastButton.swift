import ReplayKit
import SwiftUI

/// The system broadcast picker, which is the only supported way to start a ReplayKit
/// broadcast. It renders as a button; tapping it shows the system sheet.
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 44, height: 44)
        )
        picker.preferredExtension = BroadcastInfo.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

enum BroadcastInfo {
    static let extensionBundleIdentifier = "ai.chesssense.app.broadcast"
}
