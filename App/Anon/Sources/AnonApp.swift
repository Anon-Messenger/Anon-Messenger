import SwiftUI
import AppKit
import AnonCore

/// The Anon logo loaded from the app bundle. Falls back to a paperplane glyph
/// when the resource isn't present (e.g. running the bare binary).
struct AnonLogoView: View {
    var size: CGFloat = 84

    private var logoImage: NSImage? {
        guard let path = Bundle.main.path(forResource: "anon", ofType: "png") else { return nil }
        return NSImage(contentsOfFile: path)
    }

    var body: some View {
        Group {
            if let logoImage = logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                ZStack {
                    Circle().fill(AnonTheme.nav).frame(width: size, height: size)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Formatting helpers

func formatHM(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

func dayKey(for date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f.string(from: date)
}

struct DateSeparator: View {
    let text: String
    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AnonTheme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.06))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Telegram-style message bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var corners: BubbleCorners {
        message.isOutgoing ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 70) }

            VStack(alignment: .trailing, spacing: 0) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.top, 7)
                    .padding(.horizontal, 12)

                HStack(spacing: 4) {
                    Text(formatHM(message.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(message.isOutgoing ? Color.green.opacity(0.8) : AnonTheme.muted)
                    if message.isOutgoing {
                        ReadTicks(isRead: message.isRead)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 3)
                .padding(.bottom, 6)
            }
            .background(message.isOutgoing ? AnonTheme.outgoingBubble : AnonTheme.incomingBubble)
            .clipShape(BubbleShape(corners: corners))
            .overlay(BubbleShape(corners: corners).stroke(Color.black.opacity(0.04), lineWidth: 1))
            .contextMenu {
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                if message.isOutgoing {
                    Button("Delete (clear locally)") { /* local-only deletion */ }
                }
            }

            if !message.isOutgoing { Spacer(minLength: 70) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

struct ReadTicks: View {
    let isRead: Bool

    var body: some View {
        HStack(spacing: -7) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            if isRead {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .foregroundColor(isRead ? Color.green : AnonTheme.muted)
    }
}

// Which corners of a bubble are rounded (Foundation-only, macOS + iOS safe).
struct BubbleCorners: OptionSet {
    let rawValue: Int
    static let topLeft     = BubbleCorners(rawValue: 1 << 0)
    static let topRight    = BubbleCorners(rawValue: 1 << 1)
    static let bottomLeft  = BubbleCorners(rawValue: 1 << 2)
    static let bottomRight = BubbleCorners(rawValue: 1 << 3)
}

struct BubbleShape: Shape {
    let corners: BubbleCorners
    let radius: CGFloat

    init(corners: BubbleCorners, radius: CGFloat = 16) {
        self.corners = corners
        self.radius = radius
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        let tl = corners.contains(.topLeft) ? r : 0
        let tr = corners.contains(.topRight) ? r : 0
        let bl = corners.contains(.bottomLeft) ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                        radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                        radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                        radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                        radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let contact: Contact
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(gradient).frame(width: size, height: size)
            Text(contact.initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var gradient: LinearGradient {
        // Canonical Telegram peer-name color, deterministic per contact.
        let base = TelegramDesignTokens.peerColor(for: contact.peer.value)
        let brighter = base.opacity(0.82)
        return LinearGradient(colors: [base, brighter], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Chat row (matches Telegram's layout)

struct ChatRow: View {
    let contact: Contact
    let lastText: String
    let lastTime: String
    let unread: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(contact: contact, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(contact.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(lastTime)
                        .font(.system(size: 12))
                        .foregroundColor(unread > 0 ? AnonTheme.accent : AnonTheme.muted)
                }
                HStack {
                    Text(lastText.isEmpty ? contact.subtitle : lastText)
                        .font(.system(size: 13))
                        .foregroundColor(AnonTheme.muted)
                        .lineLimit(1)
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AnonTheme.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? AnonTheme.accent.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Onboarding (no phone number)

struct OnboardingView: View {
    @State private var displayName = ""
    let onFinish: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            AnonLogoView(size: 84)

            Text("Anon")
                .font(.system(size: 38, weight: .bold))
                .padding(.top, 18)

            Text("No phone number. No account. No username.\nYour identity stays on this device.")
                .font(.system(size: 14))
                .foregroundColor(AnonTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(spacing: 0) {
                TextField("Display name (optional)", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
            .frame(width: 320)
            .padding(.top, 28)

            Button(action: { onFinish(displayName.trimmingCharacters(in: .whitespaces).isEmpty ? "You" : displayName.trimmingCharacters(in: .whitespaces)) }) {
                Text("Start Messaging")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 320, height: 44)
                    .background(AnonTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            Text("Connections are established only by one-time invitation links or QR codes.")
                .font(.system(size: 11))
                .foregroundColor(AnonTheme.muted)
                .multilineTextAlignment(.center)
                .frame(width: 320)
                .padding(.top, 20)
            Spacer()
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(AnonTheme.chatBackground)
    }
}

// MARK: - Settings / privacy sheet

struct SettingsView: View {
    let displayName: String
    let fingerprint: String
    let onRotate: () -> Void
    let onWipe: () -> Void
    let onDismiss: () -> Void

    @State private var confirmWipe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button { onDismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundColor(AnonTheme.muted)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("PROFILE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AnonTheme.muted)
                Text(displayName).font(.system(size: 17, weight: .semibold))
                Text("No phone number · no username · no account")
                    .font(.system(size: 13))
                    .foregroundColor(AnonTheme.muted)

                Text("PRIVACY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AnonTheme.muted)
                    .padding(.top, 8)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ephemeral identity fingerprint")
                            .font(.system(size: 13, weight: .medium))
                        Text(fingerprint)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AnonTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fingerprint, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.vertical, 6)

                Button(action: onRotate) {
                    Label("Rotate identity", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                if confirmWipe {
                    HStack(spacing: 10) {
                        Button(action: onWipe) {
                            Text("Confirm wipe")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        Button("Cancel") { confirmWipe = false }
                            .buttonStyle(.plain)
                            .foregroundColor(AnonTheme.accent)
                    }
                } else {
                    Button(action: { confirmWipe = true }) {
                        Label("Emergency wipe (panic)", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }

                Text("Panic wipe destroys all local messages, session keys, and the ephemeral identity on this device.")
                    .font(.system(size: 11))
                    .foregroundColor(AnonTheme.muted)
                    .padding(.top, 2)
            }
            .padding()
            Spacer()
        }
        .frame(minWidth: 420, minHeight: 440)
    }
}

// MARK: - Main app (side-by-side, Telegram-like)

struct AnonApp: View {
    @ObservedObject var local: ChatController
    var displayName: String
    var onRotate: (() -> Void)?

    private let contacts: [Contact] = [
        Contact(id: "contact-1", peer: "anon-remote-1", displayName: "Nova", subtitle: "offline · mesh", initials: "N"),
        Contact(id: "contact-2", peer: "anon-remote-2", displayName: "Relay", subtitle: "offline · 2 hops", initials: "R")
    ]

    @State private var selectedContactID = "contact-1"
    @State private var draft = ""
    @State private var searchQuery = ""
    @State private var showSettings = false

    private var selectedContact: Contact {
        contacts.first { $0.id == selectedContactID } ?? contacts[0]
    }

    private var filteredContacts: [Contact] {
        guard !searchQuery.isEmpty else { return contacts }
        return contacts.filter { $0.displayName.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var selectedMessages: [ChatMessage] {
        local.messages.filter { message in
            if message.isOutgoing { return message.recipient == selectedContact.peer }
            return message.sender == selectedContact.peer
        }
    }

    private var messageGroups: [(header: String, items: [ChatMessage])] {
        var groups: [(String, [ChatMessage])] = []
        for message in selectedMessages {
            let key = dayKey(for: message.timestamp)
            if groups.last?.0 == key {
                groups[groups.count - 1].1.append(message)
            } else {
                groups.append((key, [message]))
            }
        }
        return groups
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            conversation
        }
        .frame(minWidth: 860, minHeight: 540)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                displayName: displayName,
                fingerprint: String(local.sessionPublicKey.base64.prefix(24)),
                onRotate: {
                    local.rotateIdentity()
                    onRotate?()
                    showSettings = false
                },
                onWipe: {
                    local.rotateIdentity()
                    onRotate?()
                    showSettings = false
                },
                onDismiss: { showSettings = false }
            )
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header: logo + "Anon" + Menu
            HStack(spacing: 6) {
                AnonLogoView(size: 26)
                Text("Anon")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(AnonTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(AnonTheme.sidebar)

            // Search (Telegram-style pill)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(AnonTheme.muted)
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(AnonTheme.sidebar)

            Divider()

            // Chat list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredContacts) { contact in
                        Button {
                            selectedContactID = contact.id
                            local.markRead(peer: contact.peer)
                        } label: {
                            ChatRow(
                                contact: contact,
                                lastText: lastText(for: contact.peer),
                                lastTime: lastTime(for: contact.peer),
                                unread: local.unreadCount(for: contact.peer),
                                selected: contact.id == selectedContactID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(AnonTheme.sidebar)
        }
        .frame(width: 300)
        .background(AnonTheme.sidebar)
    }

    // MARK: Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            // Conversation header
            HStack(spacing: 10) {
                AvatarView(contact: selectedContact, size: 32)
                Text(selectedContact.displayName)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(selectedContact.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(AnonTheme.nav)
            .foregroundColor(.white)

            Divider()

            // Message feed
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(messageGroups, id: \.header) { group in
                            DateSeparator(text: group.header)
                            ForEach(group.items) { message in
                                MessageBubble(message: message)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .background(AnonTheme.chatBackground)
                .onChange(of: selectedMessages.count) { _ in
                    if let last = selectedMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Composer (Telegram-like)
            HStack(spacing: 10) {
                Button { /* attach */ } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundColor(AnonTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Attach (coming soon)")

                TextField("Message", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(draft.trimmingCharacters(in: .whitespaces).isEmpty ? AnonTheme.muted : AnonTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        local.send(text: text, to: selectedContact.peer)
        draft = ""
    }

    private func lastText(for peer: PeerRef) -> String {
        local.messages.filter { message in
            message.isOutgoing ? message.recipient == peer : message.sender == peer
        }.last?.text ?? ""
    }

    private func lastTime(for peer: PeerRef) -> String {
        guard let last = local.messages.filter({ message in
            message.isOutgoing ? message.recipient == peer : message.sender == peer
        }).last else { return "" }
        return formatHM(last.timestamp)
    }
}

// MARK: - Root (onboarding gate)

struct AppRoot: View {
    @ObservedObject var local: ChatController
    @State private var displayName = ""

    var body: some View {
        if displayName.isEmpty {
            OnboardingView(onFinish: { displayName = $0 })
        } else {
            AnonApp(local: local, displayName: displayName, onRotate: nil)
        }
    }
}
