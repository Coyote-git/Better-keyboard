import UIKit

enum KeyboardThemeName: String {
    case apple
    case nge
}

struct KeyboardTheme {

    // MARK: - Current theme

    static var current: KeyboardTheme = loadSaved()

    static func switchTo(_ name: KeyboardThemeName) {
        current = theme(for: name)
        UserDefaults.standard.set(name.rawValue, forKey: "keyboardTheme")
    }

    static func cycle() {
        let next: KeyboardThemeName = current.name == .apple ? .nge : .apple
        switchTo(next)
    }

    private static func loadSaved() -> KeyboardTheme {
        let raw = UserDefaults.standard.string(forKey: "keyboardTheme") ?? "apple"
        let name = KeyboardThemeName(rawValue: raw) ?? .apple
        return theme(for: name)
    }

    private static func theme(for name: KeyboardThemeName) -> KeyboardTheme {
        switch name {
        case .apple: return .appleTheme
        case .nge:   return .ngeTheme
        }
    }

    // MARK: - Properties

    let name: KeyboardThemeName

    // Background
    let backgroundColor: UIColor

    // Key segments
    let keyFillColor: UIColor
    let keyStrokeColor: UIColor
    let keyStrokeWidth: CGFloat
    let keyHighlightFillColor: UIColor
    let keyGapInsetDeg: CGFloat  // angular gap between keys

    // Letter labels
    let innerRingTextColor: UIColor
    let outerRingTextColor: UIColor
    let innerRingFontSize: CGFloat
    let outerRingFontSize: CGFloat
    let innerRingFontWeight: UIFont.Weight
    let outerRingFontWeight: UIFont.Weight
    let useMonospaceFont: Bool

    // Highlight / glow
    let glowColor: UIColor
    let highlightTextColor: UIColor

    // Ring arcs
    let ringArcStrokeColor: UIColor
    let ringArcDashed: Bool

    // Gap zones
    let backspaceFillColor: UIColor
    let backspaceIconColor: UIColor
    let spaceFillColor: UIColor
    let spaceIconColor: UIColor
    let gapStrokeColor: UIColor

    // Center zone
    let centerFillColor: UIColor
    let centerStrokeColor: UIColor

    // Buttons
    let buttonFillColor: UIColor
    let buttonTextColor: UIColor
    let buttonCornerRadius: CGFloat
    let buttonBorderColor: UIColor?
    let buttonBorderWidth: CGFloat

    // Key brackets
    let showKeyBrackets: Bool

    // Swipe trail
    let trailEnabled: Bool
    let trailColor: UIColor
    let trailGlowRadius: CGFloat
    let trailGlowOpacity: Float
    let trailLineWidth: CGFloat

    // MARK: - Apple Theme

    static let appleTheme = KeyboardTheme(
        name: .apple,

        backgroundColor: UIColor(white: 0, alpha: 1),

        keyFillColor: .clear,
        keyStrokeColor: UIColor(white: 0.35, alpha: 1),
        keyStrokeWidth: 1.0,
        keyHighlightFillColor: UIColor(white: 0.17, alpha: 1),
        keyGapInsetDeg: 1.5,

        innerRingTextColor: .white,
        outerRingTextColor: UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1), // #EBEBEB
        innerRingFontSize: 18,
        outerRingFontSize: 14,
        innerRingFontWeight: .bold,
        outerRingFontWeight: .medium,
        useMonospaceFont: false,

        glowColor: UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1), // #D4E5F7 ice blue
        highlightTextColor: UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1),

        ringArcStrokeColor: UIColor(white: 0.15, alpha: 1),
        ringArcDashed: false,

        backspaceFillColor: UIColor(white: 0.1, alpha: 0.5),
        backspaceIconColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1), // #FF453A
        spaceFillColor: UIColor(white: 0.1, alpha: 0.5),
        spaceIconColor: UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1), // #D4E5F7 icy blue
        gapStrokeColor: UIColor(white: 0.15, alpha: 0.3),

        centerFillColor: .clear,
        centerStrokeColor: .clear,

        buttonFillColor: .clear,
        buttonTextColor: .white,
        buttonCornerRadius: 14,
        buttonBorderColor: nil,
        buttonBorderWidth: 0,

        showKeyBrackets: false,

        trailEnabled: false,
        trailColor: UIColor(red: 0.83, green: 0.90, blue: 0.97, alpha: 1), // #D4E5F7
        trailGlowRadius: 6,
        trailGlowOpacity: 0.7,
        trailLineWidth: 2.5
    )

    // MARK: - NGE Theme

    static let ngeTheme = KeyboardTheme(
        name: .nge,

        backgroundColor: UIColor(white: 0, alpha: 1),

        keyFillColor: .clear,
        keyStrokeColor: UIColor(red: 0.23, green: 0.10, blue: 0.10, alpha: 1), // #3A1A1A
        keyStrokeWidth: 0.75,
        keyHighlightFillColor: UIColor(red: 0.10, green: 0.04, blue: 0.04, alpha: 1),
        keyGapInsetDeg: 1.0,

        innerRingTextColor: UIColor(red: 1.0, green: 0.42, blue: 0.07, alpha: 1), // #FF6A13
        outerRingTextColor: UIColor(red: 0.90, green: 0.38, blue: 0.06, alpha: 1), // #E6600F
        innerRingFontSize: 18,
        outerRingFontSize: 14,
        innerRingFontWeight: .bold,
        outerRingFontWeight: .medium,
        useMonospaceFont: true,

        glowColor: UIColor(red: 1.0, green: 0.42, blue: 0.07, alpha: 1), // #FF6A13
        highlightTextColor: UIColor(red: 1.0, green: 0.42, blue: 0.07, alpha: 1),

        ringArcStrokeColor: UIColor(red: 0.23, green: 0.10, blue: 0.10, alpha: 1), // #3A1A1A
        ringArcDashed: false,

        backspaceFillColor: UIColor(red: 0.10, green: 0.04, blue: 0.04, alpha: 0.8), // #1A0A0A
        backspaceIconColor: UIColor(red: 0.80, green: 0.13, blue: 0.0, alpha: 1), // #CC2200
        spaceFillColor: UIColor(red: 0.10, green: 0.04, blue: 0.04, alpha: 0.5),
        spaceIconColor: UIColor(red: 0.80, green: 0.13, blue: 0.0, alpha: 1), // #CC2200 red
        gapStrokeColor: UIColor(red: 0.23, green: 0.10, blue: 0.10, alpha: 0.5),

        centerFillColor: .clear,
        centerStrokeColor: .clear,

        buttonFillColor: .clear,
        buttonTextColor: UIColor(red: 1.0, green: 0.42, blue: 0.07, alpha: 1), // #FF6A13
        buttonCornerRadius: 5,
        buttonBorderColor: UIColor(red: 0.23, green: 0.10, blue: 0.10, alpha: 1), // #3A1A1A
        buttonBorderWidth: 1,

        showKeyBrackets: true,

        trailEnabled: true,
        trailColor: UIColor(red: 1.0, green: 0.42, blue: 0.07, alpha: 1), // #FF6A13
        trailGlowRadius: 10,
        trailGlowOpacity: 0.9,
        trailLineWidth: 2.5
    )
}
