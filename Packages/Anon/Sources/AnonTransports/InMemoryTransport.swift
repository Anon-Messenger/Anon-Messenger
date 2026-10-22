import AnonCore
import AnonRouter

/// A deterministic, fully-mocked `AnonTransport` used for unit tests and for
/// simulator/demo wiring before the real BLE/i2pd backends are attached.
///
/// Reachability and promptness are configurable so tests can exercise every
/// routing branch without any hardware or network. An optional `onOutbound`
/// hook lets two instances be bridged into a loopback pair.
public final class InMemoryTransport: AnonTransport {
    public let transportID: TransportID
    public let priority: TransportPriority

    /// Reachability reported by `isPeerReachable` for any peer.
    public var peerReachability: TransportReachability
    public var reachesAllPeers: Bool
    public var promptDelivery: Bool

    /// Invoked after the transport hands an envelope to the network. Useful for
    /// bridging two in-memory transports together in demos/tests.
    public var onOutbound: ((Envelope, PeerRef) -> Void)?

    private var receiveHandler: ((Envelope) -> Void)?
    private var sends: [(Envelope, PeerRef, (DeliveryAck) -> Void)] = []

    public init(
        transportID: TransportID,
        priority: TransportPriority,
        reachability: TransportReachability = .available,
        reachesAllPeers: Bool = true,
        promptDelivery: Bool = true
    ) {
        self.transportID = transportID
        self.priority = priority
        self.peerReachability = reachability
        self.reachesAllPeers = reachesAllPeers
        self.promptDelivery = promptDelivery
    }

    public var reachability: TransportReachability { peerReachability }

    public func isPeerReachable(_ ref: PeerRef) -> Bool {
        reachesAllPeers
    }

    public func canDeliverPromptly(to ref: PeerRef) -> Bool {
        promptDelivery
    }

    public func send(_ envelope: Envelope, to ref: PeerRef, completion: @escaping (DeliveryAck) -> Void) {
        sends.append((envelope, ref, completion))
        onOutbound?(envelope, ref)
        completion(DeliveryAck(messageID: envelope.messageID, transportID: transportID, accepted: true))
    }

    public func registerReceiveHandler(_ handler: @escaping (Envelope) -> Void) {
        receiveHandler = handler
    }

    /// Simulate an inbound envelope arriving on this transport.
    public func deliverInbound(_ envelope: Envelope) {
        receiveHandler?(envelope)
    }

    /// Number of send invocations recorded.
    public var sendCount: Int {
        sends.count
    }

    /// All recorded send invocations (for assertions).
    public var recordedSends: [(Envelope, PeerRef)] {
        sends.map { ($0.0, $0.1) }
    }
}