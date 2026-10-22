import SwiftUI

/// Telegram-inspired palette, sourced from factual design tokens in
/// `TelegramDesignTokens.swift`. Chat background/bubbles stay close to
/// Telegram's day theme; the accent is the canonical `0x0088ff`.
enum AnonTheme {
    /// Sidebar navigation tint (Telegram's classic teal-blue).
    static let nav = Color(red: 0.34, green: 0.51, blue: 0.64)

    /// Chat area background.
    static let chatBackground = Color(red: 0.91, green: 0.92, blue: 0.95)

    /// Sidebar background.
    static let sidebar = Color.white

    /// Outgoing message bubble (Telegram's soft green).
    static let outgoingBubble = Color(red: 0.87, green: 0.98, blue: 0.82)

    /// Incoming message bubble.
    static let incomingBubble = Color.white

    /// Canonical Telegram accent blue (`defaultDayAccentColor`, 0x0088ff).
    static let accent = TelegramDesignTokens.color(hex: TelegramDesignTokens.accentHex)

    /// Muted text color (Telegram's `messageTextColor`, 0x8e8e93).
    static let muted = TelegramDesignTokens.color(hex: TelegramDesignTokens.ChatList.messageHex)
}