import SwiftUI
import CoreText

// Manrope and Inter ship as variable fonts — one file per family carrying the
// whole weight range rather than a file per weight. iOS only exposes the
// family's default instance by name, and both families default to a weight far
// off what the UI wants (Manrope's default is ExtraLight), so every weight here
// is cut at runtime by setting the variation axes on the descriptor rather than
// by asking for a named face that doesn't exist.
enum BlipperFont {

    /// Manrope. The wordmark, and nothing else — it's the app's signature, and
    /// spending it on ordinary headers is what dilutes it.
    static let display = "Manrope"
    /// Inter. Everything else, down to and including headers and names.
    static let ui = "Inter"

    // Four-character axis tags as the integer identifiers CoreText wants.
    private enum Axis {
        static let weight = 0x77676874        // 'wght'
        static let opticalSize = 0x6F70737A   // 'opsz'
    }

    // Asking for an optical size outside the axis' range doesn't clamp, it
    // fails to match. Manrope has no optical axis at all, so it isn't listed.
    private static let opticalRange: [String: ClosedRange<CGFloat>] = [
        ui: 14...32,
    ]

    // Manrope's weight axis stops at 800, and an out-of-range request fails to
    // match rather than clamping.
    private static let weightRange: [String: ClosedRange<CGFloat>] = [
        display: 200...800,
        ui: 100...900,
    ]

    // MARK: - Registration

    // Belt and braces alongside the Info.plist UIAppFonts entries: if the
    // resources land somewhere the plist doesn't name, this still finds them,
    // and re-registering an already-registered font is a no-op we can ignore.
    private static let register: Void = {
        for name in [display, ui] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    // MARK: - Font construction

    // Descriptor matching is the expensive part, so resolved faces are held.
    // The size category is in the key because Dynamic Type is applied here
    // rather than by SwiftUI — see `scaled(_:)` below.
    private struct CacheKey: Hashable {
        let family: String
        let size: CGFloat
        let weight: CGFloat
        let style: UIFont.TextStyle?
        let category: UIContentSizeCategory
        let monospacedDigits: Bool
    }

    private static var cache: [CacheKey: UIFont] = [:]

    static func uiFont(_ family: String, size: CGFloat, weight: CGFloat, monospacedDigits: Bool = false) -> UIFont {
        _ = register

        let clampedWeight = weightRange[family].map { min(max(weight, $0.lowerBound), $0.upperBound) } ?? weight
        var variations: [Int: CGFloat] = [Axis.weight: clampedWeight]
        if let range = opticalRange[family] {
            variations[Axis.opticalSize] = min(max(size, range.lowerBound), range.upperBound)
        }

        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: family,
            // Untyped on purpose: this attribute has no UIFontDescriptor alias.
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
        ]
        if monospacedDigits {
            // Tabular figures, for numbers that must not reflow as they change —
            // a running countdown, a code being typed in.
            attributes[.featureSettings] = [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]
        }

        let descriptor = UIFontDescriptor(fontAttributes: attributes)
        // If the family never registered, this falls back to the system face at
        // the right size rather than rendering nothing.
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The point size iOS uses for a text style at the default content size —
    /// the sizes the app already lays out against, so swapping the typeface in
    /// doesn't move anything.
    static func baseSize(for style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
    }

    /// Scaled for the reader's Dynamic Type setting. `Font(uiFont)` is a fixed
    /// size to SwiftUI, so the scaling has to happen before the handoff — which
    /// is fine, because these are built inside `body` and rebuilt when the
    /// content size category changes.
    static func scaled(
        _ family: String,
        style: UIFont.TextStyle,
        weight: CGFloat,
        monospacedDigits: Bool = false
    ) -> Font {
        let category = UITraitCollection.current.preferredContentSizeCategory
        let key = CacheKey(
            family: family, size: 0, weight: weight,
            style: style, category: category, monospacedDigits: monospacedDigits
        )
        if let hit = cache[key] { return Font(hit) }

        // The optical size axis is set from the size the glyphs actually render
        // at, so scaling happens before the face is cut rather than after.
        let metrics = UIFontMetrics(forTextStyle: style)
        let size = metrics.scaledValue(for: baseSize(for: style))
        let font = uiFont(family, size: size, weight: weight, monospacedDigits: monospacedDigits)
        cache[key] = font
        return Font(font)
    }

    /// A face at a literal point size, for text measured against something
    /// other than Dynamic Type — initials sized off their avatar, say.
    static func fixed(_ family: String, size: CGFloat, weight: CGFloat) -> Font {
        let key = CacheKey(
            family: family, size: size, weight: weight,
            style: nil, category: .large, monospacedDigits: false
        )
        if let hit = cache[key] { return Font(hit) }
        let font = uiFont(family, size: size, weight: weight)
        cache[key] = font
        return Font(font)
    }
}

// MARK: - SwiftUI entry points

extension Font {

    /// Manrope, at the metrics of a system text style. The wordmark only —
    /// headers and names take `blipperUI` like everything else.
    static func blipperDisplay(_ style: UIFont.TextStyle = .body, weight: CGFloat = 800) -> Font {
        BlipperFont.scaled(BlipperFont.display, style: style, weight: weight)
    }

    /// Inter, at the metrics of a system text style. Everything that isn't the
    /// wordmark, headers and names included.
    static func blipperUI(
        _ style: UIFont.TextStyle = .body,
        weight: CGFloat = 400,
        monospacedDigits: Bool = false
    ) -> Font {
        BlipperFont.scaled(BlipperFont.ui, style: style, weight: weight, monospacedDigits: monospacedDigits)
    }

    /// Manrope at a literal size.
    static func blipperDisplay(fixedSize: CGFloat, weight: CGFloat = 800) -> Font {
        BlipperFont.fixed(BlipperFont.display, size: fixedSize, weight: weight)
    }

    /// Inter at a literal size — avatar initials and small circular badges,
    /// sized off their container rather than off Dynamic Type.
    static func blipperUI(fixedSize: CGFloat, weight: CGFloat = 400) -> Font {
        BlipperFont.fixed(BlipperFont.ui, size: fixedSize, weight: weight)
    }
}
