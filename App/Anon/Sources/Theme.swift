import SwiftUI

/// Telegram-inspired palette.
enum AnonTheme {
    /// Sidebar navigation tint (Telegram's classic iOS teal-blue).
    static let nav = Color(red: 0.34, green: 0.51, blue: 0.64)

    /// Chat area background.
    static let chatBackground = Color(red: 0.91, green: 0.92, blue: 0.95)

    /// Sidebar background.
    static let sidebar = Color.white

    /// Outgoing message bubble (Telegram's soft green).
    static let outgoingBubble = Color(red: 0.87, green: 0.98, blue: 0.82)

    /// Incoming message bubble.
    static let incomingBubble = Color.white

    /// Primary accent used for buttons and highlights.
    static let accent = Color(red: 0.20, green: 0.53, blue: 0.80)

    /// Muted text color.
    static let muted = Color(white: 0.45)
}