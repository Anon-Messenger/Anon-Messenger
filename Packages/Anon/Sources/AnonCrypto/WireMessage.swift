import CryptoKit
import Foundation

/// A one-time invitation encoding an ephemeral session key.
///
/// An invitation is exactly what Anon exchanges out-of-band (QR/NFC). It
/// carries **no long-term identifier** — only a fresh ephemeral key and an
/// optional display label. The URL is short enough for a QR code.
public struct AnonInvitation: Equatable {
    public static let scheme = "anon"
    public static let version = 1

    public let displayName: String
    public let sessionKey: SessionPublicKey

    public init(displayName: String, sessionKey: SessionPublicKey) {
        self.displayName = displayName
        self.sessionKey = sessionKey
    }

    public var link: String {
        "anon://invite?v=\(Self.version)&n=\(urlEncode(displayName))&key=\(sessionKey.base64)"
    }

    public init?(link: String) {
        guard link.hasPrefix("\(Self.scheme)://invite?") else { return nil }
        guard let query = link.split(separator: "?", maxSplits: 1).last else { return nil }
        var name = "contact"
        var keyString: String?
        var versionValid = false

        for item in query.split(separator: "&") {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "v": versionValid = (parts[1] == String(Self.version))
            case "n": name = parts[1].removingPercentEncoding ?? parts[1]
            case "key": keyString = parts[1]
            default: continue
            }
        }

        guard versionValid, let keyString = keyString, let key = SessionPublicKey(base64: keyString) else {
            return nil
        }
        self.init(displayName: name, sessionKey: key)
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

/// An authenticated wire message: `senderKey || seal(text)`.
///
/// The envelope the router transports carries `sealedPayload` where the whole
/// `WireMessage` is encoded. The receiver derives the session secret from its
/// own ephemeral private key and the sender's public key, then opens the inner
/// AEAD box. A message from an unknown key is rejected.
public struct WireMessage: Codable, Equatable {
    public static let version = 1

    public let version: Int
    public let senderKey: SessionPublicKey
    public let sealed: Data

    public init(version: Int = WireMessage.version, senderKey: SessionPublicKey, sealed: Data) {
        self.version = version
        self.senderKey = senderKey
        self.sealed = sealed
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) -> WireMessage? {
        try? JSONDecoder().decode(WireMessage.self, from: data)
    }
}