import AnonCore
import AnonRouter
import AnonTransports
import Combine
import Foundation

/// A UI-level chat message. For the M0 app shell the payload is plain text;
/// the real controller seals content with double-ratchet ciphertext — the
/// router only ever sees the opaque bytes in `Envelope`.
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let sender: PeerRef
    let recipient: PeerRef?
    let text: String
    let timestamp: Date
    let isOutgoing: Bool
}

/// A contact listed in the chat list and addressed by the controller.
struct Contact: Identifiable {
    let id: String
    let peer: PeerRef
    let displayName: String
    let subtitle: String
    let initials: String
}

/// Wraps one `MessageRouter` + one `AnonTransport` for a single profile (one
/// "device"). The app shell runs two instances — the local profile and
/// simulated remote contacts — bridged over a simulated mesh.
final class ChatController: ObservableObject {
    @Published var messages: [ChatMessage] = []

    let peer: PeerRef
    let transportNode: InMemoryTransport

    /// When set, inbound text triggers an automatic reply after a short delay.
    /// The local profile leaves this `nil`; remote contacts use a canned reply
    /// so the end-to-end path is demonstrable.
    var autoReply: ((String) -> String)?

    private let router: MessageRouter

    init(peer: PeerRef) {
        self.peer = peer
        self.transportNode = InMemoryTransport(transportID: .mesh, priority: .mesh)
        self.router = MessageRouter()
        self.router.register(transportNode)
        self.router.onReceive { [weak self] envelope in
            self?.handleReceive(envelope)
        }
    }

    /// Insert a local-only incoming message (demo seeding; no wire traffic).
    func seedIncoming(text: String, from sender: PeerRef) {
        let message = ChatMessage(
            id: "seed-\(UUID().uuidString)",
            sender: sender,
            recipient: nil,
            text: text,
            timestamp: Date(),
            isOutgoing: false
        )
        messages.append(message)
    }

    func send(text: String, to recipient: PeerRef) {
        let id = MessageID.random()
        let message = ChatMessage(
            id: id.uuid,
            sender: peer,
            recipient: recipient,
            text: text,
            timestamp: Date(),
            isOutgoing: true
        )
        messages.append(message)

        // Plain demo payload: "text|sender". The router never inspects these
        // bytes; the real controller substitutes ratchet ciphertext here.
        let payload = (text + "|" + peer.value).data(using: .utf8) ?? Data()
        let envelope = Envelope(recipientRef: recipient, sealedPayload: payload, messageID: id)
        _ = router.send(envelope, to: recipient)
    }

    private func handleReceive(_ envelope: Envelope) {
        guard let raw = String(data: envelope.sealedPayload, encoding: .utf8) else { return }
        let parts = raw.components(separatedBy: "|")
        let text = parts.first ?? ""
        let sender = PeerRef(parts.count > 1 ? parts[1] : envelope.recipientRef.value)

        let message = ChatMessage(
            id: envelope.messageID.uuid,
            sender: sender,
            recipient: nil,
            text: text,
            timestamp: Date(),
            isOutgoing: false
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.messages.append(message)
            if let autoReply = self.autoReply {
                let reply = autoReply(text)
                let delay = Double.random(in: 0.8...1.6)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.send(text: reply, to: sender)
                }
            }
        }
    }
}

/// Bridges in-memory mesh transports so an envelope sent by one node is
/// delivered into the recipient node's inbound handler. This stands in for the
/// real BLE radio until M1 attaches the bitchat mesh engine to `AnonTransport`.
final class MeshBus {
    private var nodes: [PeerRef: InMemoryTransport] = [:]

    func connect(_ lhs: (PeerRef, InMemoryTransport), _ rhs: (PeerRef, InMemoryTransport)) {
        nodes[lhs.0] = lhs.1
        nodes[rhs.0] = rhs.1
        lhs.1.onOutbound = { [weak self] envelope, recipient in
            self?.deliver(to: recipient, envelope: envelope)
        }
        rhs.1.onOutbound = { [weak self] envelope, recipient in
            self?.deliver(to: recipient, envelope: envelope)
        }
    }

    private func deliver(to recipient: PeerRef, envelope: Envelope) {
        nodes[recipient]?.deliverInbound(envelope)
    }
}