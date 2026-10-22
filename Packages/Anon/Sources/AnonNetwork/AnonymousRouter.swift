import AnonCore
import Foundation

/// Kind of embedded or companion anonymous network router.
public enum RouterKind: String, Hashable, Codable {
    case i2p
    case tor
}

/// Lifecycle/health state of a router. The app surfaces this without ever
/// leaking identifiers.
public enum RouterStatus: String, Hashable, Codable {
    case off
    case booting
    case ready
    case degraded
    case error
}

/// A SOCKS proxy endpoint exposed by the router. All internet transports dial
/// through this endpoint, so transport code never depends on a concrete router.
public struct SocksEndpoint: Hashable, Codable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

/// The seam between transports and the anonymous network layer. Transports
/// depend on this protocol (and never on a concrete router). Both embedded i2pd
/// and the optional Arti/Tor router implement it.
public protocol AnonymousRouter: AnyObject {
    var kind: RouterKind { get }
    var socksProxy: SocksEndpoint { get }
    var status: RouterStatus { get }

    /// Boot the router and block until `status` changes. Implementations must
    /// be safe to call once, then no-op on subsequent calls.
    func start() async throws

    /// Tear down the router and release its network resources.
    func stop() async

    /// Register a callback for status changes. Called on an arbitrary queue.
    func setStatusHandler(_ handler: @escaping (RouterStatus) -> Void)
}