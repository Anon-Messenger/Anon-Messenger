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
///
/// Every message is sealed end-to-end with `AnonCrypto` before it enters the
/// router: the router and the mesh transport only ever see a `WireMessage`
/// whose payload is `senderKey || seal(plaintext)`.
final class ChatController: ObservableObject {
    @Published var messages: [ChatMessage] = []

    let peer: PeerRef
    let transportNode: InMemoryTransport

    /// When set, inbound text triggers an automatic reply after a short delay.
    /// The local profile leaves this `nil`; remote contacts use canned replies.
    var autoReply: ((String) -> String)?

    /// This profile's ephemeral session. A fresh one is created per
    /// profile/launch; its public key is never a long-term, globally visible
    /// identifier.
    private let session = EphemeralSession()

    private let router: MessageRouter

    /// Derived symmetric key per contact, indexed by the contact's session key.
    private var keysByPeerPublicKey: [SessionPublicKey: SymmetricKey] = [:]

    /// Maps a local `PeerRef` to that contact's ephemeral public key.
    private var publicKeyByPeer: [PeerRef: SessionPublicKey] = [:]

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

    /// Complete the X25519 handshake side for a peer's public key.
    func sharedSecret(with peerKey: SessionPublicKey) -> Data? {
        session.sharedSecret(with: peerKey)
    }

    /// Install a contact's ephemeral public key and the derived symmetric
    /// session key. This is the in-process equivalent of completing an
    /// invitation handshake; over a real transport the same keys are exchanged
    /// via a one-time `anon://invite?...` link.
    func installContactKey(_ key: SymmetricKey, peer ref: PeerRef, publicKey: SessionPublicKey) {
        keysByPeerPublicKey[publicKey] = key
        publicKeyByPeer[ref] = publicKey
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

        // Build the sealed wire payload.
        guard
            let peerKey = publicKeyByPeer[recipient],
            let sessionKey = keysByPeerPublicKey[peerKey],
            let sealed = try? sealText(text, using: sessionKey)
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
        guard let sessionKey = keysByPeerPublicKey[wire.senderKey] else { return }
        guard let text = try? openText(wire.sealed, using: sessionKey) else { return }

        let sender = peerRef(for: wire.senderKey) ?? envelope.recipientRef
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

    a.installContactKey(deriveSessionKey(from: aSecret), peer: refB, publicKey: b.sessionPublicKey)
    b.installContactKey(deriveSessionKey(from: bSecret), peer: refA, publicKey: a.sessionPublicKey)
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