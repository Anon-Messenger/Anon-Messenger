import SwiftUI

/// Canonical Telegram-iOS design values, expressed here as original Anon code.
///
/// These are *factual* color/metric values extracted from the Telegram-iOS
/// presentation-data layer (`submodules/TelegramPresentationData` and
/// `TelegramCore/Sources/State/ManagedPeerColorUpdates.swift`). Individual
/// color values are facts, not creative expression, so they are reproduced to
/// keep Anon visually faithful while remaining clean-room: no Telegram code is
/// copied into this repository (Telegram-iOS is GPL; Anon is AGPL and must not
/// absorb its implementation).
enum TelegramDesignTokens {

    /// `defaultDayAccentColor` — the Telegram iOS accent blue.
    static let accentHex: UInt32 = 0x0088ff

    /// Day chat-list palette.
    enum ChatList {
        /// `titleColor`
        static let titleHex: UInt32 = 0x000000
        /// `messageTextColor` (preview text)
        static let messageHex: UInt32 = 0x8e8e93
        /// `freeTextColor`
        static let freeHex: UInt32 = 0x6d6d72
        /// `pinnedItemBackgroundColor`
        static let pinnedItemHex: UInt32 = 0xf7f7f7
    }

    /// The seven preset peer-name colors used for contact identity accents.
    /// Order matches the static peer-color map in Telegram's
    /// `ManagedPeerColorUpdates.swift`.
    static let peerNameHexPalette: [UInt32] = [
        0xcc5049, // red
        0xd67722, // orange
        0x955cdb, // violet
        0x40a920, // green
        0x309eba, // cyan
        0x368ad1, // blue
        0xc7508b, // pink
    ]

    /// Converts an ARGB-ordered hex value (as used by Telegram) to a SwiftUI
    /// color. Telegram constants are `0xRRGGBB`; the alpha is implicit 1.0.
    static func color(hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }

    /// Deterministic peer-name color for a stable string key (local label only).
    static func peerColor(for key: String) -> Color {
        let sum = key.utf8.reduce(0) { $0 + Int($1) }
        let idx = sum % peerNameHexPalette.count
        return color(hex: peerNameHexPalette[idx])
    }
}