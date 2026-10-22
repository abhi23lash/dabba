import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Design tokens for dabba. Every color adapts between the light ("Paper")
/// and dark ("Night") appearances; never hard-code a color in a view.
enum Paper {
    // MARK: Color
    static let paper       = Color(light: 0xF6F2EA, dark: 0x171614) // page and board ground
    static let paperRaised = Color(light: 0xFFFDF8, dark: 0x211F1C) // sheets above the page
    static let ink         = Color(light: 0x22201C, dark: 0xEDE8DF) // writing, primary text
    static let inkMuted    = Color(light: 0x6B655B, dark: 0xA39D92) // labels, hints, dates
    static let hairline    = Color(light: 0xDDD6C9, dark: 0x34312C) // rules and dividers
    static let accent      = Color(light: 0xB5502F, dark: 0xE8896A) // cursor, focus, strike-through

    // MARK: Type (New York for writing, SF Pro for interface)
    static let page     = Font.system(size: 19, design: .serif)
    static let question = Font.system(size: 24, design: .serif).italic()
    static let landing  = Font.system(size: 22, weight: .semibold, design: .serif)
    static let label    = Font.system(size: 13, weight: .medium)

    // MARK: Layout
    static let column: CGFloat = 640   // ~65 characters of `page`
    static let margin: CGFloat = 32
}

extension Color {
    /// A color that resolves to `light` or `dark` with the system appearance.
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
