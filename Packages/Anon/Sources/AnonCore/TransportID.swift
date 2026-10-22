/// Identity of a transport. The router uses these values to sort by priority and
/// to record which transport actually delivered an envelope.
///
/// Priority is `mesh` (offline) first, then `smpI2P` (primary internet), then
/// `nostrI2P` (opt-in public channel fallback).
public enum TransportID: String, Hashable, Codable, CaseIterable {
    case mesh
    case smpI2P
    case nostrI2P

    public var label: String { rawValue }

    /// Stable ordering used for transport selection. Lower wins.
    public var priorityOrder: Int {
        switch self {
        case .mesh: return 0
        case .smpI2P: return 1
        case .nostrI2P: return 2
        }
    }
}

/// Comparable by priority so transports can be sorted directly.
public enum TransportPriority: Int, Comparable, Hashable {
    case mesh = 0
    case smpI2P = 1
    case nostrI2P = 2

    public static func < (lhs: TransportPriority, rhs: TransportPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var transportID: TransportID {
        switch self {
        case .mesh: return .mesh
        case .smpI2P: return .smpI2P
        case .nostrI2P: return .nostrI2P
        }
    }
}

/// Observable state of a transport, surfaced by the router.
public enum TransportReachability: String, Hashable, Codable {
    /// Radio/link up; peers may currently be reachable.
    case available
    /// Usable but degraded (e.g. low radio power, slow link); prompts are unhelpful.
    case degraded
    /// Off-line, unavailable, or disabled.
    case unavailable
}