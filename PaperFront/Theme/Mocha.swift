import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

/// Catppuccin Mocha palette — https://catppuccin.com/palette
enum Mocha {
    static let rosewater = Color(hex: 0xf5e0dc)
    static let flamingo = Color(hex: 0xf2cdcd)
    static let pink = Color(hex: 0xf5c2e7)
    static let mauve = Color(hex: 0xcba6f7)
    static let red = Color(hex: 0xf38ba8)
    static let maroon = Color(hex: 0xeba0ac)
    static let peach = Color(hex: 0xfab387)
    static let yellow = Color(hex: 0xf9e2af)
    static let green = Color(hex: 0xa6e3a1)
    static let teal = Color(hex: 0x94e2d5)
    static let sky = Color(hex: 0x89dceb)
    static let sapphire = Color(hex: 0x74c7ec)
    static let blue = Color(hex: 0x89b4fa)
    static let lavender = Color(hex: 0xb4befe)
    static let text = Color(hex: 0xcdd6f4)
    static let subtext1 = Color(hex: 0xbac2de)
    static let subtext0 = Color(hex: 0xa6adc8)
    static let overlay2 = Color(hex: 0x9399b2)
    static let overlay1 = Color(hex: 0x7f849c)
    static let overlay0 = Color(hex: 0x6c7086)
    static let surface2 = Color(hex: 0x585b70)
    static let surface1 = Color(hex: 0x45475a)
    static let surface0 = Color(hex: 0x313244)
    static let base = Color(hex: 0x1e1e2e)
    static let mantle = Color(hex: 0x181825)
    static let crust = Color(hex: 0x11111b)

    static let baseUI = UIColor(hex: 0x1e1e2e)
    static let textUI = UIColor(hex: 0xcdd6f4)
    static let crustUI = UIColor(hex: 0x11111b)
}

/// Colours offered for highlights and pens (all Catppuccin Mocha).
enum Swatch: String, CaseIterable, Codable, Identifiable {
    case yellow, peach, red, pink, mauve, blue, sky, teal, green, ink, snow

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .yellow: return 0xf9e2af
        case .peach: return 0xfab387
        case .red: return 0xf38ba8
        case .pink: return 0xf5c2e7
        case .mauve: return 0xcba6f7
        case .blue: return 0x89b4fa
        case .sky: return 0x89dceb
        case .teal: return 0x94e2d5
        case .green: return 0xa6e3a1
        case .ink: return 0x11111b
        case .snow: return 0xcdd6f4
        }
    }

    var color: Color { Color(hex: hex) }
    var uiColor: UIColor { UIColor(hex: hex) }
    var label: String { rawValue.capitalized }

    static let highlightChoices: [Swatch] = [.yellow, .green, .sky, .pink, .peach, .mauve]
    static let penChoices: [Swatch] = [.red, .peach, .yellow, .green, .teal, .blue, .mauve, .pink, .ink, .snow]
}
