import CryptoKit
import Foundation

/// A bidirectional session cipher with directional keys and context binding.
///
/// Two weaknesses of using a single shared symmetric key for both directions
/// are closed here:
///
/// 1. **Directionality (reflection resistance).** The A→B key differs from the
///    B→A key because each is derived over the *ordered* public-key pair. A
///    ciphertext produced by A cannot be reflected back to A and authenticate,
///    and cannot be confused with a message B created.
/// 2. **Session binding (key-substitution resistance).** All AEAD tags are
///    bound to the canonical `(PeerA, PeerB)` session identity as associated
///    data, so a valid ciphertext cannot be transplanted into a different
///    session or against a substituted key.
public struct SessionCipher {
    public let sendKey: SymmetricKey
    public let recvKey: SymmetricKey
    private let sessionAAD: Data

    /// - Parameters:
    ///   - myKey: this party's ephemeral public key.
    ///   - peerKey: the remote party's ephemeral public key.
    ///   - sharedSecret: the X25519 shared secret derived by both parties.
    public init(myKey: SessionPublicKey, peerKey: SessionPublicKey, sharedSecret: Data) {
        let material = SymmetricKey(data: sharedSecret)

        // Directional keys are derived over the ordered pair so A→B differs
        // from B→A. Both parties derive the same two keys, but each assigns
        // them to send/recv from their own perspective.
        self.sendKey = Self.derive(material, tag: "anon/v1/session", pair: (myKey.raw, peerKey.raw))
        self.recvKey = Self.derive(material, tag: "anon/v1/session", pair: (peerKey.raw, myKey.raw))

        // Canonical session identity is direction-independent (sorted), so both
        // sides derive identical associated data for tag verification.
        let a = myKey.raw
        let b = peerKey.raw
        let ordered = a.lexicographicallyPrecedes(b) ? (a, b) : (b, a)
        var aad = Data("anon/v1/session".utf8)
        aad.append(ordered.0)
        aad.append(ordered.1)
        self.sessionAAD = aad
    }

    /// Encrypt `plaintext` for the peer (A→B direction from this party).
    public func seal(_ plaintext: Data) throws -> Data {
        try sealMessage(plaintext, using: sendKey, authenticating: sessionAAD)
    }

    /// Decrypt and authenticate a payload from the peer (B→A direction).
    public func open(_ sealed: Data) throws -> Data {
        try openMessage(sealed, using: recvKey, authenticating: sessionAAD)
    }

    private static func derive(_ material: SymmetricKey, tag: String, pair: (Data, Data)) -> SymmetricKey {
        var info = Data(tag.utf8)
        info.append(pair.0)
        info.append(pair.1)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )
    }
}