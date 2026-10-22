import CryptoKit
import Foundation

/// Errors surfaced by the E2EE layer.
public enum AnonCryptoError: Error, Equatable {
    case invalidKey
    case invalidPayload
}

/// Symmetric key derived from a shared X25519 secret using HKDF-SHA256.
public func deriveSessionKey(from sharedSecret: Data, salt: Data = Data(), info: String = "anon/v1/e2ee") -> SymmetricKey {
    let keyingMaterial = SymmetricKey(data: sharedSecret)
    let infoData = info.data(using: .utf8)!
    let derived = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: keyingMaterial,
        salt: salt,
        info: infoData,
        outputByteCount: 32
    )
    return derived
}

/// Seal a plaintext `Data` payload into an AEAD envelope with a random nonce.
/// The result is `nonce || ciphertext || tag`, suitable for opaque storage in
/// the router's `Envelope.sealedPayload`.
///
/// `authenticating` is AES-GCM associated data: it is bound into the
/// authentication tag but not encrypted. Binding the session context here
/// prevents an attacker from replaying or transplanting a valid ciphertext
/// into a different session (key-substitution / reflection attacks).
public func sealMessage(_ plaintext: Data, using key: SymmetricKey, authenticating aad: Data = Data()) throws -> Data {
    let nonce = AES.GCM.Nonce()
    let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
    return nonce.withUnsafeBytes { Data($0) } + box.ciphertext + box.tag
}

/// Open an AEAD envelope previously produced by `sealMessage`.
/// The supplied associated data must match exactly or opening fails.
public func openMessage(_ sealed: Data, using key: SymmetricKey, authenticating aad: Data = Data()) throws -> Data {
    // nonce (12) + ciphertext + tag (16)
    guard sealed.count > 28 else { throw AnonCryptoError.invalidPayload }
    let nonceData = sealed.prefix(12)
    let tagData = sealed.suffix(16)
    let ciphertext = sealed.dropFirst(12).dropLast(16)

    guard let nonce = try? AES.GCM.Nonce(data: nonceData) else { throw AnonCryptoError.invalidPayload }
    let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)
    return try AES.GCM.open(box, using: key, authenticating: aad)
}

/// Convenience wrappers for String payloads.
public func sealText(_ text: String, using key: SymmetricKey, authenticating aad: Data = Data()) throws -> Data {
    try sealMessage(Data(text.utf8), using: key, authenticating: aad)
}

public func openText(_ sealed: Data, using key: SymmetricKey, authenticating aad: Data = Data()) throws -> String {
    String(decoding: try openMessage(sealed, using: key, authenticating: aad), as: UTF8.self)
}