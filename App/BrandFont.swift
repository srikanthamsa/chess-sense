import SwiftUI
import UIKit

/// The app's type voice: a high-contrast display serif for the big statement, SF for
/// everything that has to be read quickly.
///
/// Instrument Serif (SIL Open Font License 1.1) ships in the bundle. It falls back to the
/// system serif if it ever fails to register, so a missing resource degrades instead of
/// crashing and the app never renders in a random default face.
enum BrandFont {
    static let displayName = "InstrumentSerif-Regular"
    static let displayItalic = "InstrumentSerif-Italic"

    static func display(_ size: CGFloat) -> Font {
        isRegistered(displayName)
            ? .custom(displayName, size: size)
            : .system(size: size, weight: .semibold, design: .serif)
    }

    static func displayItalicFace(_ size: CGFloat) -> Font {
        isRegistered(displayItalic)
            ? .custom(displayItalic, size: size)
            : .system(size: size, weight: .regular, design: .serif).italic()
    }

    /// Section labels: small, spaced-out, in the same serif so the page has one voice.
    static func label(_ size: CGFloat) -> Font {
        display(size)
    }

    private static func isRegistered(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }
}

/// Large numerals keep SF's tabular figures; words take the serif.
extension Font {
    static func brandDisplay(_ size: CGFloat) -> Font { BrandFont.display(size) }
    static func brandLabel(_ size: CGFloat) -> Font { BrandFont.label(size) }
}
