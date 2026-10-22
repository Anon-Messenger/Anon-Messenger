import AnonCore
import AnonRouter
import AnonTransports
import AnonCrypto
import Combine
import CryptoKit
import Foundation

/// A UI-level chat message.
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let sender: PeerRef
    let recipient: PeerRef?
    let text: String
    let timestamp: Date
    let isOutgoing: Bool
    /// `true` once the receiver has acknowledged the message (read receipt).
    var isRead: Bool = false
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
/// "device"), and owns that profile's ephemeral session key.
final class ChatController: ObservableObject {
    @Published var messages: [ChatMessage] = []

    let peer: PeerRef
    let transportNode: InMemoryTransport

    /// When set, inbound text triggers an automatic reply after a short delay.
    var autoReply: ((String) -> String)?

    /// This profile's ephemeral session. A fresh one is created per
    /// profile/launch; its public key is never a long-term, globally visible
    /// identifier.
    private var session = EphemeralSession()

    private let router: MessageRouter

    /// Directional, session-bound cipher per contact, indexed by the contact's
    /// ephemeral session key. The cipher prevents reflection and key
    /// substitution (see `SessionCipher`).
    private var ciphersByPeerPublicKey: [SessionPublicKey: SessionCipher] = [:]

    /// Maps a local `PeerRef` to that contact's ephemeral public key.
    private var publicKeyByPeer: [PeerRef: SessionPublicKey] = [:]

    /// Unread inbound message count per peer.
    private var unreadByPeer: [PeerRef: Int] = [:]

    init(peer: PeerRef) {
        self.peer = peer
        self.transportNode = InMemoryTransport(transportID: .mesh, priority: .mesh)
        self.router = MessageRouter()
        self.router.register(transportNode)
        self.router.onReceive { [weak self] envelope in
            self?.handleReceive(envelope)
        }
    }

    /// The key this profile advertises to contacts (QR invitation payload).
    var sessionPublicKey: SessionPublicKey { session.publicKey }

    /// Number of unread inbound messages for a peer.
    func unreadCount(for peer: PeerRef) -> Int {
        unreadByPeer[peer] ?? 0
    }

    /// Clear the unread count once the user has viewed the conversation.
    func markRead(peer: PeerRef) {
        unreadByPeer[peer] = 0
    }

    /// Complete the X25519 handshake side for a peer's public key.
    func sharedSecret(with peerKey: SessionPublicKey) -> Data? {
        session.sharedSecret(with: peerKey)
    }

    /// Install a contact's ephemeral public key and the derived session cipher.
    func installContactCipher(_ cipher: SessionCipher, peer ref: PeerRef, publicKey: SessionPublicKey) {
        ciphersByPeerPublicKey[publicKey] = cipher
        publicKeyByPeer[ref] = publicKey
    }

    /// Insert a local-only incoming message (demo seeding; no wire traffic).
    func seedIncoming(text: String, from sender: PeerRef, id: String = "seed-\(UUID().uuidString)") {
        let message = ChatMessage(
            id: id,
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

        guard
            let peerKey = publicKeyByPeer[recipient],
            let cipher = ciphersByPeerPublicKey[peerKey],
            let sealed = try? cipher.seal(Data(text.utf8))
        else {
            appendOutgoing(id: id, text: text, to: recipient, note: "🔒 no session")
            return
        }

        let wire = WireMessage(senderKey: session.publicKey, sealed: sealed)
        guard let payload = try? wire.encoded() else { return }

        appendOutgoing(id: id, text: text, to: recipient, note: nil)
        let envelope = Envelope(recipientRef: recipient, sealedPayload: payload, messageID: id)
        _ = router.send(envelope, to: recipient)
    }

    /// Wipe all message content and rotate to a brand-new ephemeral identity.
    /// No long-term identifier survives a rotation; any established session key
    /// becomes invalid and must be re-established from a fresh invitation.
    func rotateIdentity() {
        messages.removeAll()
        unreadByPeer.removeAll()
        session = EphemeralSession()
        ciphersByPeerPublicKey.removeAll()
        publicKeyByPeer.removeAll()
    }

    private func appendOutgoing(id: MessageID, text: String, to recipient: PeerRef, note: String?) {
        let finalText = note.map { "\(text) \($0)" } ?? text
        let message = ChatMessage(
            id: id.uuid,
            sender: peer,
            recipient: recipient,
            text: finalText,
            timestamp: Date(),
            isOutgoing: true
        )
        messages.append(message)
    }

    private func handleReceive(_ envelope: Envelope) {
        guard let wire = WireMessage.decode(envelope.sealedPayload) else { return }
        guard let cipher = ciphersByPeerPublicKey[wire.senderKey] else { return }
        guard let textData = try? cipher.open(wire.sealed) else { return }
        let text = String(decoding: textData, as: UTF8.self)

        let sender = peerRef(for: wire.senderKey) ?? envelope.recipientRef
        unreadByPeer[sender, default: 0] += 1
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
            // Mark any prior outgoing messages to this peer as read.
            for index in self.messages.indices where self.messages[index].isOutgoing && self.messages[index].recipient == sender {
                self.messages[index].isRead = true
            }
            if let autoReply = self.autoReply {
                let reply = autoReply(text)
                let delay = Double.random(in: 0.8...1.6)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.send(text: reply, to: sender)
                }
            }
        }
    }

    private func peerRef(for key: SessionPublicKey) -> PeerRef? {
        publicKeyByPeer.first { $0.value == key }?.key
    }
}

/// Complete the ephemeral key agreement between two controllers and install the
/// derived session keys on both sides.
func establishContactKey(
    between a: ChatController,
    peerA refA: PeerRef,
    and b: ChatController,
    peerB refB: PeerRef
) {
    guard
        let aSecret = a.sharedSecret(with: b.sessionPublicKey),
        let bSecret = b.sharedSecret(with: a.sessionPublicKey)
    else { return }

    let aCipher = SessionCipher(myKey: a.sessionPublicKey, peerKey: b.sessionPublicKey, sharedSecret: aSecret)
    let bCipher = SessionCipher(myKey: b.sessionPublicKey, peerKey: a.sessionPublicKey, sharedSecret: bSecret)
    a.installContactCipher(aCipher, peer: refB, publicKey: b.sessionPublicKey)
    b.installContactCipher(bCipher, peer: refA, publicKey: a.sessionPublicKey)
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