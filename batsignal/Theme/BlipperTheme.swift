import SwiftUI

// The Blipper palette: dusk over the water in Santa Cruz — a dark, blue
// dominant base with two warm accents that each carry their own meaning.
//
// Amber is identity and action (anything representing a person, a place, or a
// primary action). Rose is status and urgency only — live indicators, ending a
// signal, destructive actions — so it stays a signal rather than decoration.
enum Blipper {

    // MARK: Base

    /// Primary dark background base, and the flat fill under cards and chips.
    static let duskNavy = Color(hex: 0x16283A)
    /// Mid-tone background, and the fill inside the map's pin shapes.
    static let swellBlue = Color(hex: 0x2F4E63)

    // MARK: Accents

    /// The signal color: an event icon's ring everywhere, its fill on the map
    /// pin and in the create/edit flow, and a running signal's time remaining.
    /// It stays out of the interactive chrome — buttons, links and icons use
    /// `moonlight` — so amber keeps meaning "a signal" rather than "tap here".
    static let amber = Color(hex: 0xE0A83F)
    /// Status/urgency accent, as a fill.
    static let rose = Color(hex: 0x93443A)
    /// The lighter, more saturated rose. Carries urgency where the dark rose
    /// would disappear — text and icons sitting directly on the dark base.
    static let roseBright = Color(hex: 0xC1594B)

    // MARK: Text

    /// Headers, names, and anything else high-emphasis.
    static let textPrimary = Color(hex: 0xEAEEEF)
    /// Timestamps, subtitles, helper text. A flat neutral gray on purpose —
    /// tinting it blue muddies its job as the quiet one.
    static let textMuted = Color(hex: 0x8A9096)
    /// The interactive color, and secondary chrome: buttons, icons, chevrons,
    /// dividers, hairlines. Backs the AccentColor asset, so `.accentColor`
    /// and the app tint both resolve here.
    static let moonlight = Color(hex: 0xC7D0D4)

    // MARK: On-accent

    // Text on an accent takes a dark, desaturated version of that same hue
    // rather than black or white, so the pairing stays warm instead of clinical.

    /// For labels and glyphs sitting on a `moonlight` fill — the filled
    /// buttons. Dusk navy rather than black, for the same reason.
    static let onMoonlight = duskNavy
    /// For labels and glyphs sitting on `amber`. Amber is an outline color
    /// now, so nothing currently sits on top of it — kept for when something
    /// does.
    static let onAmber = Color(hex: 0x3A2506)
    /// For labels and glyphs sitting on `rose`.
    static let onRose = Color(hex: 0x2E100A)
    /// The lighter alternative on a dark rose fill, where `onRose` is too heavy.
    static let onRoseLight = Color(hex: 0xE8D3CE)

    // MARK: Derived surfaces

    /// Card and panel surfaces. Held just short of opaque so the gradient
    /// behind them bleeds through and they stay part of the scene.
    static let surface = duskNavy.opacity(0.92)
    /// A card sitting on another card, which needs to separate from it.
    static let surfaceRaised = swellBlue.opacity(0.55)
    /// Hairline borders and dividers — moonlight at low opacity rather than a
    /// flat gray, so they never compete with actual content.
    static let hairline = moonlight.opacity(0.15)
    /// The unfilled remainder of a progress track.
    static let track = moonlight.opacity(0.12)

    /// The full-screen dusk gradient: dark navy sky at the top easing down into
    /// the mid-blue of the water. Two tones only — the warm stops that used to
    /// close it out have gone, so nothing on a background competes with the
    /// rose that signals urgency. Backgrounds only; cards and badges sit on
    /// flat `duskNavy` instead.
    static let backgroundGradient = LinearGradient(
        colors: [duskNavy, swellBlue],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    /// The dusk gradient behind a full screen, plus the scroll background
    /// clearing that lets it actually show through. Inert on a screen that
    /// isn't a scroll view.
    ///
    /// Note this can't also set the row background: `listRowBackground` does
    /// not propagate from the list down to its rows, only from a Section, so
    /// rows that don't draw a card of their own need `blipperRows()` on their
    /// Section or they keep the system's near-black grouped fill.
    func blipperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Blipper.backgroundGradient.ignoresSafeArea())
    }

    /// The card surface behind the rows of a Section whose rows don't build a
    /// card themselves. Apply to the Section, not the List — see above.
    func blipperRows() -> some View {
        listRowBackground(Blipper.surface)
    }

    /// A soft accent glow. Always a colored halo rather than a hard drop
    /// shadow — the palette's light sources are diffused through fog.
    func blipperGlow(_ color: Color = Blipper.amber, radius: CGFloat = 12, opacity: Double = 0.35) -> some View {
        shadow(color: color.opacity(opacity), radius: radius)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
