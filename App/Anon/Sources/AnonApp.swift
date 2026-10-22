import SwiftUI
import AnonCore

/// Telegram-style message bubble.
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }
            Text(message.text)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.isOutgoing ? AnonTheme.outgoingBubble : AnonTheme.incomingBubble)
                .clipShape(BubbleShape(corners: message.isOutgoing ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]))
                .overlay(
                    BubbleShape(corners: message.isOutgoing ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
            if !message.isOutgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

/// Which corners of a bubble are rounded. Foundation-only (no UIKit), so the
/// same shape works on macOS and iOS.
struct BubbleCorners: OptionSet {
    let rawValue: Int
    static let topLeft     = BubbleCorners(rawValue: 1 << 0)
    static let topRight    = BubbleCorners(rawValue: 1 << 1)
    static let bottomLeft  = BubbleCorners(rawValue: 1 << 2)
    static let bottomRight = BubbleCorners(rawValue: 1 << 3)
}

/// Rounded bubble with one square corner, like Telegram's message bubbles.
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

/// One row in the chat list.
struct ChatRow: View {
    let contact: Contact
    let lastText: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(linGradient)
                    .frame(width: 48, height: 48)
                Text(contact.initials)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text(lastText.isEmpty ? contact.subtitle : lastText)
                    .font(.system(size: 13))
                    .foregroundColor(AnonTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selected ? AnonTheme.accent.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
    }

    private var linGradient: LinearGradient {
        switch contact.id {
        case "contact-1": return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "contact-2": return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// The main window: sidebar chat list + message feed + composer.
struct AnonApp: View {
    @ObservedObject var local: ChatController

    private let contacts: [Contact] = [
        Contact(id: "contact-1", peer: "anon-remote-1", displayName: "Nova (mesh)", subtitle: "offline · mesh", initials: "N"),
        Contact(id: "contact-2", peer: "anon-remote-2", displayName: "Relay (mesh)", subtitle: "offline · 2 hops", initials: "R")
    ]

    @State private var selectedContactID = "contact-1"
    @State private var draft = ""

    private var selectedContact: Contact {
        contacts.first { $0.id == selectedContactID } ?? contacts[0]
    }

    private var selectedMessages: [ChatMessage] {
        local.messages.filter { message in
            if message.isOutgoing {
                return message.recipient == selectedContact.peer
            }
            return message.sender == selectedContact.peer
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            conversation
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
                .background(AnonTheme.sidebar)
            Divider()
            List {
                ForEach(contacts) { contact in
                    Button {
                        selectedContactID = contact.id
                    } label: {
                        ChatRow(contact: contact, lastText: lastText(for: contact.peer), selected: contact.id == selectedContactID)
                            .buttonStyle(.plain)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(SidebarListStyle())
            .background(AnonTheme.sidebar)
        }
        .frame(width: 260)
        .background(AnonTheme.sidebar)
    }

    private var header: some View {
        HStack {
            Text("Anon")
                .font(.system(size: 20, weight: .bold))
            Spacer()
            Circle()
                .fill(Color.green)
                .frame(width: 9, height: 9)
            Text("mesh")
                .font(.system(size: 12))
                .foregroundColor(AnonTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            // Conversation header
            HStack {
                Text(selectedContact.displayName)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(selectedContact.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AnonTheme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AnonTheme.nav)
            .foregroundColor(.white)

            Divider()

            // Message feed
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(selectedMessages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(AnonTheme.chatBackground)

            Divider()

            // Composer
            HStack(spacing: 10) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
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
            if message.isOutgoing {
                return message.recipient == peer
            }
            return message.sender == peer
        }.last?.text ?? ""
    }
}