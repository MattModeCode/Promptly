import AppKit

// MARK: - Lightfall design system
//
// The single source of truth for Promptly's look: a strictly dark, opaque, monochrome
// ("Lightfall") system chosen via a judged design review over three alternatives. No hue anywhere —
// depth comes from a surface ladder + black-only shadow, emphasis from luminance + weight + space.
// Kept under the name `Palette` (with back-compat aliases at the bottom) so existing call sites keep
// compiling while they migrate to the richer token set.
//
// Accessibility is structural: zero hue means colour-blindness and Reduce-Transparency are non-issues
// by construction; the Increase-Contrast-aware accessors below strengthen the selection signal live
// (re-read on each redraw); layer-cached control borders restrengthen the next time a surface opens.

enum Palette {

    // MARK: Primitives

    private static func hex(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
    private static func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }

    /// System "Increase Contrast" — read live so tokens strengthen without a relaunch.
    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    // MARK: Surface ladder (opaque; each lift pairs with an elevation step)

    static let void     = hex(0x08, 0x08, 0x0B)   // space behind the floating panel
    static let surface0 = hex(0x0E, 0x0E, 0x13)   // ground floor — palette + window chrome
    static let surface1 = hex(0x14, 0x14, 0x1A)   // hover
    static let surface2 = hex(0x1A, 0x1A, 0x21)   // inset controls / selected chrome / sheets
    static let surface3 = hex(0x20, 0x20, 0x28)   // top elevation — chips, menus, tooltips

    // MARK: Text (all AAA on surface-0 except tertiary, which is hints-only)

    static let textPrimary   = hex(0xE6, 0xEA, 0xF0)   // ~14.5:1
    static let textSecondary = hex(0x9A, 0xA3, 0xB2)   // ~7.2:1
    static let textTertiary  = hex(0x6B, 0x74, 0x80)   // ~4.1:1 (below WCAG AA) — DECORATIVE hints ONLY
    static let textDisabled  = hex(0x45, 0x4C, 0x59)
    static let matched       = NSColor.white           // fuzzy-matched characters

    // MARK: Selection ("Lightfall" — four stacked colour-independent cues)

    static var selectedFill: NSColor {
        NSColor(srgbRed: 230 / 255, green: 236 / 255, blue: 245 / 255, alpha: increaseContrast ? 0.16 : 0.10)
    }
    static let selectedFillPulse = NSColor(srgbRed: 230 / 255, green: 236 / 255, blue: 245 / 255, alpha: 0.16)
    static var selectedRail: NSColor {
        increaseContrast ? .white : NSColor(srgbRed: 230 / 255, green: 234 / 255, blue: 240 / 255, alpha: 0.92)
    }
    static let selectedRailGlow = NSColor(srgbRed: 230 / 255, green: 234 / 255, blue: 240 / 255, alpha: 0.28)
    static let selectedBevel    = white(0.07)

    // MARK: Borders

    static var hairline: NSColor      { white(increaseContrast ? 0.14 : 0.06) }
    static var borderDefault: NSColor { white(increaseContrast ? 0.20 : 0.10) }
    static let borderFocus            = white(0.28)
    static let panelEdgeInner         = white(0.08)

    // MARK: Component tokens

    static let pinnedChipFill    = hex(0x20, 0x20, 0x28)       // solid plate — "permanent promise"
    static let ghostChipBorder   = white(0.10)                 // dashed border — "today's guess"
    static let keycapFill        = white(0.05)
    static let primaryButtonFill = NSColor(srgbRed: 238 / 255, green: 242 / 255, blue: 248 / 255, alpha: 0.94)
    static let dangerSurface     = white(0.05)                 // destructive = luminance + friction, never red

    // MARK: Radii (3-step — kills the old 5/6 drift)

    enum Radius {
        static let control: CGFloat = 6    // inputs, buttons, popups, sidebar/list rows, hotkey field
        static let card: CGFloat = 8       // palette rows, Library cards
        static let container: CGFloat = 12 // panel, window, sheets, AX window
        static let chip: CGFloat = 5       // HUD chips, keycaps
    }

    // MARK: Spacing (8px grid, 4px half-step)

    enum Space {
        static let micro: CGFloat = 2, xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, xl2: CGFloat = 24, xl3: CGFloat = 32
        static let xl4: CGFloat = 40, xl5: CGFloat = 48
    }

    // MARK: Elevation (black-only; single-layer approximation of the two-layer spec)

    struct Elevation { let radius: CGFloat; let opacity: Float; let yOffset: CGFloat }
    static let elev1 = Elevation(radius: 2, opacity: 0.40, yOffset: -1)
    static let elev2 = Elevation(radius: 12, opacity: 0.50, yOffset: -4)
    static let elev3 = Elevation(radius: 32, opacity: 0.55, yOffset: -12)

    /// Apply a black drop shadow to a layer-backed view. The view must not clip (masksToBounds=false).
    static func applyElevation(_ e: Elevation, to view: NSView) {
        view.wantsLayer = true
        view.shadow = NSShadow()
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = e.opacity
        view.layer?.shadowRadius = e.radius
        view.layer?.shadowOffset = CGSize(width: 0, height: e.yOffset)
        view.layer?.masksToBounds = false
    }

    // MARK: Fonts — one monospace voice (JetBrains Mono), four weights + graceful fallback

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    static func monoMedium(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Medium", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    }
    static func monoSemibold(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-SemiBold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .semibold)
    }
    static func monoBold(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    }

    // Semantic type scale
    static var displayFont: NSFont      { monoBold(28) }
    static var titleLgFont: NSFont      { monoSemibold(18) }
    static var paletteInputFont: NSFont { mono(15) }
    static var rowTitleFont: NSFont     { monoMedium(14) }
    static var bodyFont: NSFont         { mono(13) }
    static var cardTitleFont: NSFont    { monoMedium(13) }
    static var secondaryFont: NSFont    { mono(12) }
    static var sectionLabelFont: NSFont { monoSemibold(11) }
    static var footerKeyFont: NSFont    { monoMedium(11) }
    static var hudNumeralFont: NSFont   { monoSemibold(11) }
    static var metaFont: NSFont         { mono(11) }

    // MARK: Back-compat aliases (existing call sites keep working during migration)

    static let panelBG = surface0
    static let primary = textPrimary
    static let secondary = textSecondary
    static let footer = textTertiary
    static var selFill: NSColor { selectedFill }
    static var selBar: NSColor { selectedRail }
    static var separator: NSColor { hairline }
}
