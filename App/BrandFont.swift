import CoreText
import SwiftUI
import UIKit

/// The app's type voice: a high-contrast display serif for the big statement, SF for
/// everything that has to be read quickly.
///
/// Two families ship in the bundle, both SIL Open Font License 1.1:
/// - Instrument Serif, for small display labels
/// - Playfair Display Italic, a variable font, for the hero word
///
/// Weight has to be asked for through CoreText when a font is variable, and the system
/// serif stands in if a face ever fails to register, so a missing resource degrades instead of
/// rendering in a random default face.
enum BrandFont {
    static let displayName = "InstrumentSerif-Regular"
    static let displayItalic = "InstrumentSerif-Italic"
    static let heroName = "PlayfairDisplay-Italic"

    static func display(_ size: CGFloat) -> Font {
        isRegistered(displayName)
            ? .custom(displayName, size: size)
            : .system(size: size, weight: .semibold, design: .serif)
    }

    /// The hero face: heavy, wide, italic.
    ///
    /// Playfair ships as a variable font, so the weight is requested as a CoreText variation
    /// rather than a separate file. 800 is ExtraBold; the italic axis stays upright-ish and
    /// high-contrast, which is the look we want for one word.
    static func hero(_ size: CGFloat) -> Font {
        Font(heroUIFont(size: size))
    }

    static func heroUIFont(size: CGFloat) -> UIFont {
        guard isRegistered(heroName), let base = UIFont(name: heroName, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: .heavy).withItalicTrait()
                ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        }
        let wght: CGFloat = 800
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(
                rawValue: kCTFontVariationAttribute as String
            ): [NSNumber(value: 0x7767_6874 /* 'wght' */): NSNumber(value: Double(wght))]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func displayItalicFace(_ size: CGFloat) -> Font {
        isRegistered(displayItalic)
            ? .custom(displayItalic, size: size)
            : .system(size: size, weight: .regular, design: .serif).italic()
    }

    /// Section labels share the display serif so the page has one voice.
    static func label(_ size: CGFloat) -> Font { display(size) }

    private static func isRegistered(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }
}

private extension UIFont {
    func withItalicTrait() -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitItalic) else { return nil }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

extension Font {
    static func brandDisplay(_ size: CGFloat) -> Font { BrandFont.display(size) }
    static func brandHero(_ size: CGFloat) -> Font { BrandFont.hero(size) }
    static func brandLabel(_ size: CGFloat) -> Font { BrandFont.label(size) }
}
