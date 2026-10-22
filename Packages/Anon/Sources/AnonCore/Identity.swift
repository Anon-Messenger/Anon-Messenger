import Foundation

/// An opaque reference to a recipient, used only locally. It must NEVER be
/// transmitted or derivable back to a global identifier. Each transport
/// interprets it via its own key registry, so the same `PeerRef` has no
/// meaning to any third party.
///
/// Anon deliberately diverges from bitchat here: there is no stable on-air
/// identifier. A `PeerRef` is a local, profile-scoped value.
public struct PeerRef: Hashable, Codable, ExpressibleByStringLiteral {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }
}

/// Transport hint carried by an envelope. Optional by design: the router picks
/// the actual transport at send time; this only records the sender's original
/// preference if any.
public struct TransportHint: Hashable, Codable {
    public let transportID: TransportID

    public init(_ transportID: TransportID) {
        self.transportID = transportID
    }
}

/// Globally unique, locally generated message identifier. Used for ack/dedup.
public struct MessageID: Hashable, Codable {
    public let uuid: String

    public init(_ uuid: String) {
        self.uuid = uuid
    }

    public static func random() -> MessageID {
        MessageID(UUID().uuidString)
    }
}

/// Time-to-live for an envelope, in seconds. Nil means "no expiry".
public struct EnvelopeTTL: Hashable, Codable {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }
}