import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#endif

/// Design tokens for dabba. Every color adapts between light and dark
/// appearances; never hard-code a color in a view.
enum Paper {
    // MARK: Color
    static let paper       = Color(light: 0xFFFFFF, dark: 0x141414) // page and board ground
    static let paperRaised = Color(light: 0xFFFFFF, dark: 0x1E1E1E) // sheets above the page
    static let ink         = Color(Platform.ink)                    // writing, primary text
    static let inkMuted    = Color(Platform.inkMuted)               // labels, hints, dates
    static let hairline    = Color(light: 0xE5E5E5, dark: 0x2E2E2E) // rules and dividers
    /// Tangent notes beside the page: pale tints of the provisional block
    /// colors (turmeric, terracotta, leaf, sky), cycled by tangent number.
    static let notes: [Color] = [
        Color(light: 0xF7E7BF, dark: 0x3A3220),
        Color(light: 0xF4D9CD, dark: 0x3B2922),
        Color(light: 0xDFEBD8, dark: 0x263124),
        Color(light: 0xDCE9F2, dark: 0x202E37),
    ]
    static func note(_ number: Int) -> Color { notes[max(number - 1, 0) % notes.count] }
    static let accent      = Color(Platform.accent)                 // cursor, focus; plain ink for now

    // MARK: Type (SF Pro throughout; quiet, easy on the eyes)
    static let page     = Font.system(size: 18)
    static let question = Font.system(size: 22, weight: .medium)
    static let landing  = Font.system(size: 20, weight: .semibold)
    static let label    = Font.system(size: 13, weight: .medium)

    // MARK: Layout
    static let column: CGFloat = 640   // ~65 characters of `page`
    static let margin: CGFloat = 32
    static let pageLineSpacing: CGFloat = 8

    /// The same tokens as UIKit / AppKit values, for the native text view.
    enum Platform {
        static let ink      = PlatformColor(light: 0x1A1A1A, dark: 0xEDEDED)
        static let inkMuted = PlatformColor(light: 0x6E6E6E, dark: 0x9A9A9A)
        static let accent   = ink
        static let page     = PlatformFont.systemFont(ofSize: 18)
    }
}

extension Color {
    /// A color that resolves to `light` or `dark` with the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(PlatformColor(light: light, dark: dark))
    }

    init(_ platform: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platform)
        #else
        self.init(uiColor: platform)
        #endif
    }
}

extension PlatformColor {
    /// A dynamic color that resolves to `light` or `dark` with the appearance.
    convenience init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
        #else
        self.init { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
        #endif
    }

    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        #if os(macOS)
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
        #else
        self.init(red: r, green: g, blue: b, alpha: 1)
        #endif
    }
}
