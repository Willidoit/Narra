import SwiftUI
import AppKit

// MARK: - Geometry

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
    /// Glass pill / floating HUD shells stay rounder than editorial surfaces.
    static let pill: CGFloat = 16
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

enum Motion {
    /// Editorial entry curve — matches `cubic-bezier(0.16, 1, 0.3, 1)`.
    static let entry: Animation = .timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
    /// State changes (hover, selection, pill swaps).
    static let snappy: Animation = .easeOut(duration: 0.2)
    /// Tiny opacity-only changes.
    static let microFade: Animation = .easeInOut(duration: 0.18)
}

// MARK: - Appearance

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Palette (warm monochrome, dual-theme)

enum Palette {
    // Light (warm bone)
    static let lightCanvas     = Color(hex: 0xFBFBFA)
    static let lightSurface    = Color(hex: 0xFFFFFF)
    static let lightSurfaceAlt = Color(hex: 0xF9F9F8)
    static let lightBorder     = Color(hex: 0xEAEAEA)
    static let lightInk        = Color(hex: 0x111111)
    static let lightInkSoft    = Color(hex: 0x2F3437)
    static let lightMuted      = Color(hex: 0x787774)

    // Dark (warm charcoal — never pure black)
    static let darkCanvas      = Color(hex: 0x14130F)
    static let darkSurface     = Color(hex: 0x1C1B17)
    static let darkSurfaceAlt  = Color(hex: 0x232218)
    static let darkBorder      = Color(hex: 0x2E2D27)
    static let darkInk         = Color(hex: 0xF2F1EC)
    static let darkInkSoft     = Color(hex: 0xD8D6CE)
    static let darkMuted       = Color(hex: 0x8A8780)

    // Adaptive accessors — resolve at draw time via NSColor dynamic provider.
    static let canvas     = Color(light: lightCanvas,     dark: darkCanvas)
    static let surface    = Color(light: lightSurface,    dark: darkSurface)
    static let surfaceAlt = Color(light: lightSurfaceAlt, dark: darkSurfaceAlt)
    static let border     = Color(light: lightBorder,     dark: darkBorder)
    static let ink        = Color(light: lightInk,        dark: darkInk)
    static let inkSoft    = Color(light: lightInkSoft,    dark: darkInkSoft)
    static let muted      = Color(light: lightMuted,      dark: darkMuted)

    // Muted pastels — used for status chips, tags, semantic accents.
    static let redBg     = Color(light: Color(hex: 0xFDEBEC), dark: Color(hex: 0x3A1F1F))
    static let redInk    = Color(light: Color(hex: 0x9F2F2D), dark: Color(hex: 0xE9A3A2))
    static let greenBg   = Color(light: Color(hex: 0xEDF3EC), dark: Color(hex: 0x1F2E20))
    static let greenInk  = Color(light: Color(hex: 0x346538), dark: Color(hex: 0xA8D0AC))
    static let blueBg    = Color(light: Color(hex: 0xE1F3FE), dark: Color(hex: 0x1A2A38))
    static let blueInk   = Color(light: Color(hex: 0x1F6C9F), dark: Color(hex: 0xA1CEEC))
    static let yellowBg  = Color(light: Color(hex: 0xFBF3DB), dark: Color(hex: 0x3A2F18))
    static let yellowInk = Color(light: Color(hex: 0x956400), dark: Color(hex: 0xE8C886))
}

// MARK: - Typography
//
// ponytail: system fonts only. Newsreader/Lyon would need bundling + registration;
// `.system(design: .serif)` (New York on macOS) gets the editorial tone for free.

enum Typography {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Iridescence
//
// HUD-only carve-out from the no-gradients rule. Stops are sampled from the
// app icon's refractive edge — violet, cyan, silver core, peach, amber — and
// are consumed exclusively by WaveformView in NotchBead. Do not use these
// stops anywhere else; everything else stays monochrome.

enum Iridescence {
    /// Left-to-right prismatic sweep matching the icon's refracted edge.
    static let stops: [Color] = [
        Color(hex: 0x8E76C9),  // cool violet
        Color(hex: 0x7BC0E8),  // cyan
        Color(hex: 0xF1EFEA),  // silver / pearl core
        Color(hex: 0xE89F8A),  // warm peach
        Color(hex: 0xD4A06A),  // soft amber
    ]

    /// Linear gradient over the stops, evenly spaced.
    static let sweep = LinearGradient(
        colors: stops,
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// Adaptive color: resolves to `dark` under dark appearance, otherwise `light`.
    init(light: Color, dark: Color) {
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(isDark ? dark : light)
        }
        self.init(nsColor: dynamic)
    }
}
