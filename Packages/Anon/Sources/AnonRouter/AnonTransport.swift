import AnonCore

/// Delivery acknowledgement returned by a transport after it hands an envelope
/// to the network. Acknowledged here means "accepted for delivery", not
/// "recipient displayed it".
public struct DeliveryAck: Hashable {
    public let messageID: MessageID
    public let transportID: TransportID
    public let accepted: Bool

    public init(messageID: MessageID, transportID: TransportID, accepted: Bool) {
        self.messageID = messageID
        self.transportID = transportID
        self.accepted = accepted
    }
}

/// A transport that can deliver envelopes. All transports implement this one
/// contract; optional capabilities should be expressed through separate
/// protocols (a bitchat lesson Anon carries forward) instead of casting to a
/// concrete transport class.
public protocol AnonTransport: AnyObject {
    var transportID: TransportID { get }
    var priority: TransportPriority { get }
    var reachability: TransportReachability { get }

    /// True when this transport currently has an addressable, active route for
    /// `ref` (e.g. an established mesh session or a pinned SMP queue).
    func isPeerReachable(_ ref: PeerRef) -> Bool

    /// True when delivery is expected to complete promptly (low latency),
    /// as opposed to store-and-forward. The router uses this to avoid
    /// demoting a fast transport in favour of a queued one.
    func canDeliverPromptly(to ref: PeerRef) -> Bool

    /// Best-effort handoff of a sealed envelope to the transport.
    /// The completion is called exactly once with an acknowledgement.
    func send(_ envelope: Envelope, to ref: PeerRef, completion: @escaping (DeliveryAck) -> Void)

    /// Register the handler that receives inbound envelopes from this
    /// transport. Implementations must be safe to call once at wiring time.
    func registerReceiveHandler(_ handler: @escaping (Envelope) -> Void)
}