import SwiftUI
import UIKit

enum ForgeTheme {
    static let ink = Color(light: 0x1C1C1E, dark: 0xF2F0EB)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x1A1917)
    static let text = Color(light: 0x1D1D1F, dark: 0xE7E5DF)
    static let body = Color(light: 0x2A2A2C, dark: 0xDDDBD4)
    static let secondary = Color(light: 0x6C6C70, dark: 0x9C9A90)
    static let soft = Color(light: 0x8A8A8E, dark: 0x908E84)
    static let tertiary = Color(light: 0xA0A0A6, dark: 0x7E7C72)
    static let faint = Color(light: 0xADADB2, dark: 0x706E65)
    static let background = Color(light: 0xFFFFFF, dark: 0x1E1D1A)
    static let subtleSurface = Color(light: 0xF5F5F7, dark: 0x24231F)
    static let chip = Color(light: 0xEEEEF0, dark: 0x2B2A25)
    static let rowHover = Color(light: 0xEBEBEE, dark: 0x2D2C27)
    static let border = Color(light: 0xE4E4E7, dark: 0x34332D)
    static let cardBorder = Color(light: 0xE7E7EA, dark: 0x302F29)
    static let imageOutline = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.10)
    })
    static let successTint = Color(light: 0xE8F3EC, dark: 0x16281E)
    static let successBorder = Color(light: 0xCBE4D6, dark: 0x254634)
    static let destructiveTint = Color(light: 0xFBF0EF, dark: 0x2B1A18)
    static let destructiveBorder = Color(light: 0xEFD9D7, dark: 0x4C322F)
    static let green = Color(light: 0x1B7A54, dark: 0x42B07E)
    static let blue = Color(light: 0x3E6C8E, dark: 0x74A6CB)
    static let red = Color(light: 0xE5484D, dark: 0xFF5D62)

    static let folderPalette: [Color] = [
        Color(hex: 0x1B7A54),
        Color(hex: 0x3E6C8E),
        Color(hex: 0xB0603C),
        Color(hex: 0x8A6D3B),
        Color(hex: 0x6D5A8C),
        Color(hex: 0x4A7A6A)
    ]

    static func folderColor(for index: Int) -> Color {
        folderPalette[index % folderPalette.count]
    }

    static func folderColor(for path: String, folders: [BuddyFolder]) -> Color {
        guard let index = folders.firstIndex(where: { $0.path == path }) else { return folderPalette[0] }
        return folderColor(for: index)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Font {
    static func forgeTitle(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func forgeBody(_ size: CGFloat = 15, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
