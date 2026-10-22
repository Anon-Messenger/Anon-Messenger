import CryptoKit
import Foundation

/// An ephemeral public key for a single contact session. The raw representation
/// is X25519; it is regenerated per invitation and never used as a long-term,
/// globally visible identifier.
public struct SessionPublicKey: Hashable, Codable {
    public let raw: Data

    public init(raw: Data) {
        self.raw = raw
    }

    public init?(base64: String) {
        guard let data = Data(base64Encoded: base64) else { return nil }
        self.init(raw: data)
    }

    public var base64: String {
        raw.base64EncodedString()
    }
}

/// An ephemeral X25519 key pair used to derive a contact session secret.
/// A fresh pair is generated for every invitation, mirroring the
/// "one-time invitation → ephemeral handshake" model from SimpleX.
public struct EphemeralSession {
    public let publicKey: SessionPublicKey
    private let privateKey: Curve25519.KeyAgreement.PrivateKey

    public init() {
        let key = Curve25519.KeyAgreement.PrivateKey()
        self.privateKey = key
        self.publicKey = SessionPublicKey(raw: key.publicKey.rawRepresentation)
    }

    public init?(rawPrivateKey: Data) {
        guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivateKey) else { return nil }
        self.privateKey = key
        self.publicKey = SessionPublicKey(raw: key.publicKey.rawRepresentation)
    }

    /// Derive a symmetric secret shared with `peerKey`. Returns `nil` if the
    /// peer's public key is malformed.
    public func sharedSecret(with peerKey: SessionPublicKey) -> Data? {
        guard let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKey.raw) else { return nil }
        guard let secret = try? privateKey.sharedSecretFromKeyAgreement(with: pub) else { return nil }
        return secret.withUnsafeBytes { Data($0) }
    }
}