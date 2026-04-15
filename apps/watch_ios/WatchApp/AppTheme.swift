import SwiftUI

/// App-wide color palette. "Dusk".
/// Mirrors `packages/ui_kit/lib/src/theme/app_theme.dart`. Keep hex values in sync
/// when either side changes — see docs/decisions.md.
enum AppTheme {
    static let dusk = Color(red: 0x3A / 255, green: 0x2E / 255, blue: 0x5C / 255)
    static let duskDeep = Color(red: 0x24 / 255, green: 0x1B / 255, blue: 0x3D / 255)
    static let midnight = Color(red: 0x12 / 255, green: 0x0D / 255, blue: 0x22 / 255)
    static let coral = Color(red: 0xF2 / 255, green: 0xA0 / 255, blue: 0x7B / 255)
    static let coralDeep = Color(red: 0xD9 / 255, green: 0x7A / 255, blue: 0x54 / 255)
    static let lilac = Color(red: 0xB9 / 255, green: 0xA7 / 255, blue: 0xE8 / 255)
    static let parchment = Color(red: 0xF7 / 255, green: 0xF3 / 255, blue: 0xEC / 255)
    static let ink = Color(red: 0x1B / 255, green: 0x16 / 255, blue: 0x28 / 255)
    static let haze = Color(red: 0x6B / 255, green: 0x63 / 255, blue: 0x80 / 255)
    static let error = Color(red: 0xD8 / 255, green: 0x59 / 255, blue: 0x4C / 255)
}
