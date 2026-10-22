import Foundation

/// A sealed, versioned unit of transfer. The router never sees plaintext: it
/// carries an opaque `sealedPayload` plus bookkeeping for ack/dedup.
public struct Envelope: Hashable, Codable {
    /// Protocol magic for Anon envelopes (v1).
    public static let currentVersion = 1

    /// Version of the envelope format.
    public let version: Int

    /// Recipient as a local, profile-scoped reference.
    public let recipientRef: PeerRef

    /// Optional sender preference. Never authoritative.
    public let transportHint: TransportHint?

    /// Ratchet ciphertext (content + message ID + timestamp).
    public let sealedPayload: Data

    /// Globally unique message identifier used for ack/dedup.
    public let messageID: MessageID

    /// Expiry for the envelope. Nil means "no expiry".
    public let ttl: EnvelopeTTL?

    public init(
        version: Int = Envelope.currentVersion,
        recipientRef: PeerRef,
        transportHint: TransportHint? = nil,
        sealedPayload: Data,
        messageID: MessageID,
        ttl: EnvelopeTTL? = nil
    ) {
        self.version = version
        self.recipientRef = recipientRef
        self.transportHint = transportHint
        self.sealedPayload = sealedPayload
        self.messageID = messageID
        self.ttl = ttl
    }
}