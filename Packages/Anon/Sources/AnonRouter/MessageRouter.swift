import AnonCore
import Foundation

/// Error describing why a send could not find a route.
public enum RouterError: Error, Equatable {
    case noAvailableTransport(recipient: PeerRef)
    case transportDisabled(recipient: PeerRef)
}

/// Outcome of a single envelope routing decision.
public struct RoutingDecision: Equatable {
    public let messageID: MessageID
    public let recipientRef: PeerRef
    public let chosenTransport: TransportID?
    /// True when the envelope was handed to a courier for late delivery.
    public let queuedForCourier: Bool

    public init(messageID: MessageID, recipientRef: PeerRef, chosenTransport: TransportID?, queuedForCourier: Bool) {
        self.messageID = messageID
        self.recipientRef = recipientRef
        self.chosenTransport = chosenTransport
        self.queuedForCourier = queuedForCourier
    }
}

/// The multi-transport message router.
///
/// It owns a set of `AnonTransport` instances and implements the priority
/// selection algorithm from the architecture (§5.2):
///
///   1. resolve recipient ref to candidate transports
///   2. pick the lowest-priority transport that is reachable and prompt
///   3. hand the envelope over, tracking the ack for dedup/retry
///   4. park for courier/late delivery when nothing is reachable
///
/// The router is hardened against resource exhaustion and stale replay:
/// - the dedup set is bounded (FIFO eviction),
/// - the outbox is bounded,
/// - parked envelopes carrying a TTL are dropped once expired.
///
/// The router is thread-safe: all state mutations happen on a serial queue.
public final class MessageRouter {
    private let queue = DispatchQueue(label: "anon.router.queue")
    private let deliveryQueue = DispatchQueue(label: "anon.router.delivery", attributes: .concurrent)

    private var transports: [TransportID: AnonTransport] = [:]
    private var inboundHandlers: [(Envelope) -> Void] = []

    /// Message IDs already dispatched or received; suppresses duplicates.
    private var dispatchedIDs = Set<String>()

    /// Insertion order for `dispatchedIDs`, used for bounded FIFO eviction.
    private var dispatchedOrder: [String] = []

    /// Maximum number of message IDs retained for deduplication.
    public var maxDedupEntries = 10_000

    /// Envelopes that could not be sent and are awaiting a later attempt.
    private var outbox: [PeerRef: [Envelope]] = [:]

    /// Time each parked message ID was enqueued, for TTL enforcement.
    private var parkedAt: [String: Date] = [:]

    /// Retry bookkeeping per envelope message ID.
    private var retryAttempts: [String: Int] = [:]

    /// Maximum number of times a parked envelope will be retried.
    public var maxRetryAttempts = 3

    /// Maximum number of envelopes parked awaiting a route.
    public var maxOutboxEntries = 1_000

    public init() {}

    // MARK: - Transport registry

    public func register(_ transport: AnonTransport) {
        queue.sync {
            transports[transport.transportID] = transport
            transport.registerReceiveHandler { [weak self] envelope in
                self?.receive(envelope)
            }
        }
    }

    public func unregister(_ transportID: TransportID) {
        _ = queue.sync {
            transports.removeValue(forKey: transportID)
        }
    }

    public func transport(_ transportID: TransportID) -> AnonTransport? {
        queue.sync { transports[transportID] }
    }

    public var registeredTransportIDs: [TransportID] {
        queue.sync { Array(transports.keys) }
    }

    // MARK: - Inbound

    public func onReceive(_ handler: @escaping (Envelope) -> Void) {
        queue.sync {
            inboundHandlers.append(handler)
        }
    }

    private func receive(_ envelope: Envelope) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let id = envelope.messageID.uuid
            guard !self.dispatchedIDs.contains(id) else { return }
            self.rememberDispatched(id)
            let handlers = self.inboundHandlers
            self.deliveryQueue.async {
                handlers.forEach { $0(envelope) }
            }
        }
    }

    /// Add a message ID to the dedup set, evicting the oldest entry when the
    /// configured bound is reached.
    private func rememberDispatched(_ id: String) {
        if dispatchedIDs.contains(id) { return }
        dispatchedIDs.insert(id)
        dispatchedOrder.append(id)
        if dispatchedOrder.count > maxDedupEntries {
            let stale = dispatchedOrder.removeFirst()
            dispatchedIDs.remove(stale)
        }
    }

    // MARK: - Outbound

    /// Queue an envelope for delivery. Returns the routing decision; delivery is
    /// asynchronous and its ack is tracked internally for dedup/retry.
    @discardableResult
    public func send(_ envelope: Envelope, to ref: PeerRef) -> RoutingDecision {
        queue.sync {
            route(envelope, to: ref)
        }
    }

    private func route(_ envelope: Envelope, to ref: PeerRef) -> RoutingDecision {
        let id = envelope.messageID.uuid
        if dispatchedIDs.contains(id) {
            // Already dispatched or received; do not duplicate.
            return RoutingDecision(messageID: envelope.messageID, recipientRef: ref, chosenTransport: nil, queuedForCourier: false)
        }

        // Never accept an already-expired envelope.
        guard !isExpired(envelope, at: Date()) else {
            return RoutingDecision(messageID: envelope.messageID, recipientRef: ref, chosenTransport: nil, queuedForCourier: false)
        }

        if let candidate = orderedCandidates(reachableFor: ref).first {
            rememberDispatched(id)
            candidate.send(envelope, to: ref) { [weak self] ack in
                guard let self = self else { return }
                self.queue.async { self.handle(ack) }
            }
            return RoutingDecision(messageID: envelope.messageID, recipientRef: ref, chosenTransport: candidate.transportID, queuedForCourier: false)
        }

        // No prompt route. Park when a transport can still store-and-forward
        // and the outbox is not full.
        let shouldHold = transports.values.contains { $0.isPeerReachable(ref) }
        if shouldHold, totalParked < maxOutboxEntries {
            outbox[ref, default: []].append(envelope)
            parkedAt[id] = Date()
            retryAttempts[id] = 0
        }
        return RoutingDecision(messageID: envelope.messageID, recipientRef: ref, chosenTransport: nil, queuedForCourier: shouldHold)
    }

    /// Highest-priority first among transports that both know the peer and can
    /// deliver promptly.
    private func orderedCandidates(reachableFor ref: PeerRef) -> [AnonTransport] {
        transports.values
            .filter { $0.reachability != .unavailable }
            .filter { $0.isPeerReachable(ref) && $0.canDeliverPromptly(to: ref) }
            .sorted { $0.priority < $1.priority }
    }

    private var totalParked: Int {
        outbox.values.map(\.count).reduce(0, +)
    }

    private func isExpired(_ envelope: Envelope, at now: Date) -> Bool {
        guard let ttl = envelope.ttl else { return false }
        guard ttl.seconds > 0 else { return true }
        return false // absolute expiry is tracked via parkedAt for queued envelopes
    }

    private func handle(_ ack: DeliveryAck) {
        let id = ack.messageID.uuid
        if ack.accepted {
            // Stay dispatched; drop any parked copy and its TTL bookkeeping.
            removeFromOutbox(messageID: ack.messageID)
        } else {
            // Transport rejected; allow a future retry.
            dispatchedIDs.remove(id)
        }
    }

    private func removeFromOutbox(messageID: MessageID) {
        let id = messageID.uuid
        for (ref, envelopes) in outbox {
            let remaining = envelopes.filter { $0.messageID.uuid != id }
            outbox[ref] = remaining.isEmpty ? nil : remaining
        }
        parkedAt.removeValue(forKey: id)
        retryAttempts.removeValue(forKey: id)
    }

    // MARK: - Retry & sweep

    /// Retry parked envelopes whose recipients are now reachable, and drop any
    /// whose TTL has elapsed. Safe to call frequently.
    public func retryParked() {
        queue.sync {
            let now = Date()
            let refs = Array(outbox.keys)
            for ref in refs {
                guard let envelopes = outbox[ref] else { continue }
                let remaining = envelopes.filter { envelope in
                    let id = envelope.messageID.uuid
                    guard !dispatchedIDs.contains(id) else { return false }

                    // Drop expired parked envelopes.
                    if let queuedAt = parkedAt[id], let ttl = envelope.ttl, ttl.seconds > 0 {
                        if now.timeIntervalSince(queuedAt) >= Double(ttl.seconds) {
                            parkedAt.removeValue(forKey: id)
                            retryAttempts.removeValue(forKey: id)
                            return false
                        }
                    }

                    let attempts = retryAttempts[id] ?? 0
                    guard attempts < maxRetryAttempts else { return false }

                    if let candidate = orderedCandidates(reachableFor: ref).first {
                        retryAttempts[id] = attempts + 1
                        rememberDispatched(id)
                        candidate.send(envelope, to: ref) { [weak self] ack in
                            guard let self = self else { return }
                            self.queue.async { self.handle(ack) }
                        }
                        return false // re-dispatched; drop from outbox
                    }
                    return true // still parked
                }
                outbox[ref] = remaining.isEmpty ? nil : remaining
            }
        }
    }

    /// Number of envelopes currently parked awaiting a route.
    public var parkedCount: Int {
        queue.sync { totalParked }
    }
}