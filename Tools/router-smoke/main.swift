import Foundation
import AnonCore
import AnonRouter
import AnonTransports
import AnonCrypto
import CryptoKit

// Plain assertion harness. XCTest is unavailable under Command Line Tools,
// so MessageRouter behavior is verified here with `swiftc` instead of `swift test`.

var failures = 0
func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS: \(label)")
    } else {
        failures += 1
        print("FAIL: \(label)")
    }
}

func makeEnvelope(_ id: MessageID = .random(), to ref: PeerRef = "peer-a") -> Envelope {
    Envelope(recipientRef: ref, sealedPayload: Data([1, 2, 3]), messageID: id)
}

// 1. Mesh preferred when reachable
do {
    let router = MessageRouter()
    let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P)
    [mesh, smp].forEach { router.register($0) }

    let d = router.send(makeEnvelope(), to: "peer-a")
    check(d.chosenTransport == .mesh, "mesh preferred when reachable")
    check(mesh.sendCount == 1 && smp.sendCount == 0, "only mesh dispatched")
}

// 2. SMP chosen when mesh cannot reach peer
do {
    let router = MessageRouter()
    let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh, reachesAllPeers: false)
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P)
    [mesh, smp].forEach { router.register($0) }

    let d = router.send(makeEnvelope(), to: "peer-a")
    check(d.chosenTransport == .smpI2P, "smp chosen when mesh unreachable")
    check(smp.sendCount == 1 && mesh.sendCount == 0, "only smp dispatched")
}

// 3. Unavailable transport never chosen
do {
    let router = MessageRouter()
    let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh, reachability: .unavailable)
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P)
    [mesh, smp].forEach { router.register($0) }

    let d = router.send(makeEnvelope(), to: "peer-a")
    check(d.chosenTransport == .smpI2P, "unavailable transport never chosen")
}

// 4. Reachable but not prompt parks for courier
do {
    let router = MessageRouter()
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)
    router.register(smp)

    let d = router.send(makeEnvelope(), to: "peer-a")
    check(d.chosenTransport == nil && d.queuedForCourier, "parks for courier")
    check(router.parkedCount == 1, "one envelope parked")
}

// 5. Retry dispatched when transport becomes prompt
do {
    let router = MessageRouter()
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)
    router.register(smp)

    router.send(makeEnvelope(), to: "peer-a")
    check(router.parkedCount == 1, "parked before retry")

    smp.promptDelivery = true
    router.retryParked()
    check(router.parkedCount == 0 && smp.sendCount == 1, "retry dispatched")
}

// 6. Unreachable transport does not park
do {
    let router = MessageRouter()
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, reachesAllPeers: false)
    router.register(smp)

    let d = router.send(makeEnvelope(), to: "peer-a")
    check(d.chosenTransport == nil && !d.queuedForCourier, "unreachable does not park")
    check(router.parkedCount == 0, "nothing parked")
}

// 7. Duplicate send suppressed
do {
    let router = MessageRouter()
    let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)
    router.register(mesh)

    let id = MessageID("fixed-id")
    _ = router.send(makeEnvelope(id), to: "peer-a")
    let second = router.send(makeEnvelope(id), to: "peer-a")
    check(second.chosenTransport == nil && !second.queuedForCourier, "duplicate send suppressed")
    check(mesh.sendCount == 1, "duplicate not dispatched")
}

// 8. Inbound deduplicated
do {
    let router = MessageRouter()
    let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)
    router.register(mesh)

    let received = LockBox(value: 0)
    router.onReceive { _ in received.increment() }

    let env = makeEnvelope(MessageID("inbound-id"))
    // deliver synchronously (in-memory transport calls handler directly)
    mesh.deliverInbound(env)
    mesh.deliverInbound(env)

    // inbound handler is async on the router queue; give it a moment
    Thread.sleep(forTimeInterval: 0.2)
    check(received.value == 1, "inbound deduplicated")
}

// 9. X25519 key agreement derives the same secret on both sides
do {
    let a = EphemeralSession()
    let b = EphemeralSession()
    let aSecret = a.sharedSecret(with: b.publicKey)
    let bSecret = b.sharedSecret(with: a.publicKey)
    check(aSecret == bSecret, "x25519 shared secret matches on both sides")
    check(aSecret != nil, "x25519 secret derived")
}

// 10. seal/open roundtrip
do {
    let key = SymmetricKey(size: .bits256)
    let sealed = try sealText("hello anon", using: key)
    let opened = try openText(sealed, using: key)
    check(opened == "hello anon", "seal/open roundtrip")
    check(sealed != Data("hello anon".utf8), "ciphertext differs from plaintext")
}

// 11. tampered payload is rejected (AEAD tag fails)
do {
    let key = SymmetricKey(size: .bits256)
    let sealed = try sealText("tamper me", using: key)
    var flipped = sealed
    flipped[flipped.index(flipped.endIndex, offsetBy: -1)] ^= 0xFF
    var rejected = false
    do {
        _ = try openMessage(flipped, using: key)
    } catch {
        rejected = true
    }
    check(rejected, "tampered ciphertext rejected")
}

// 12. invitation link roundtrip
do {
    let session = EphemeralSession()
    let invite = AnonInvitation(displayName: "Nova", sessionKey: session.publicKey)
    let parsed = AnonInvitation(link: invite.link)
    check(parsed == invite, "invitation link roundtrip")
    check(invite.link.hasPrefix("anon://invite?") , "invitation link scheme")
}

// 13. wire message encode/decode roundtrip
do {
    let key = SymmetricKey(size: .bits256)
    let sealed = try sealText("wire", using: key)
    let sender = EphemeralSession()
    let wire = WireMessage(senderKey: sender.publicKey, sealed: sealed)
    let decoded = try WireMessage.decode(wire.encoded())
    check(decoded?.sealed == sealed, "wire message encode/decode roundtrip")
}

// 14. SessionCipher: directional roundtrip (A→B and B→A)
do {
    let a = EphemeralSession()
    let b = EphemeralSession()
    let aCipher = SessionCipher(myKey: a.publicKey, peerKey: b.publicKey, sharedSecret: a.sharedSecret(with: b.publicKey)!)
    let bCipher = SessionCipher(myKey: b.publicKey, peerKey: a.publicKey, sharedSecret: b.sharedSecret(with: a.publicKey)!)

    let fromA = try aCipher.seal(Data("a→b".utf8))
    check(String(decoding: try bCipher.open(fromA), as: UTF8.self) == "a→b", "session cipher a→b roundtrip")

    let fromB = try bCipher.seal(Data("b→a".utf8))
    check(String(decoding: try aCipher.open(fromB), as: UTF8.self) == "b→a", "session cipher b→a roundtrip")
}

// 15. Reflection attack rejected (A's own ciphertext cannot be opened by A).
do {
    let a = EphemeralSession()
    let b = EphemeralSession()
    let aCipher = SessionCipher(myKey: a.publicKey, peerKey: b.publicKey, sharedSecret: a.sharedSecret(with: b.publicKey)!)
    let sealed = try aCipher.seal(Data("reflect me".utf8))

    var rejected = false
    do {
        _ = try aCipher.open(sealed)
    } catch {
        rejected = true
    }
    check(rejected, "reflected ciphertext rejected")
}

// 16. Cross-session / key substitution rejected.
do {
    let a = EphemeralSession()
    let b = EphemeralSession()
    let c = EphemeralSession()
    let aCipher = SessionCipher(myKey: a.publicKey, peerKey: b.publicKey, sharedSecret: a.sharedSecret(with: b.publicKey)!)
    let cCipher = SessionCipher(myKey: c.publicKey, peerKey: b.publicKey, sharedSecret: c.sharedSecret(with: b.publicKey)!)
    let sealed = try aCipher.seal(Data("cross session".utf8))

    var rejected = false
    do {
        _ = try cCipher.open(sealed)
    } catch {
        rejected = true
    }
    check(rejected, "cross-session ciphertext rejected")
}

// 17. Already-expired envelope is never accepted or parked.
do {
    let router = MessageRouter()
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)
    router.register(smp)

    let envelope = Envelope(
        recipientRef: "peer-a",
        sealedPayload: Data([1]),
        messageID: MessageID.random(),
        ttl: EnvelopeTTL(seconds: 0)
    )
    let d = router.send(envelope, to: "peer-a")
    check(d.chosenTransport == nil && !d.queuedForCourier, "expired envelope not queued")
    check(router.parkedCount == 0, "expired envelope not parked")
}

// 18. Parked envelope is dropped once its TTL elapses.
do {
    let router = MessageRouter()
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)
    router.register(smp)

    let envelope = Envelope(
        recipientRef: "peer-a",
        sealedPayload: Data([1]),
        messageID: MessageID.random(),
        ttl: EnvelopeTTL(seconds: 1)
    )
    router.send(envelope, to: "peer-a")
    check(router.parkedCount == 1, "parked before ttl expiry")

    Thread.sleep(forTimeInterval: 1.1)
    router.retryParked()
    check(router.parkedCount == 0, "parked envelope dropped after ttl expiry")
    check(smp.sendCount == 0, "expired envelope never dispatched")
}

// 19. Dedup set is bounded (FIFO eviction).
do {
    let router = MessageRouter()
    let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)
    router.register(mesh)
    router.maxDedupEntries = 3

    let ids = (0..<5).map { MessageID("dedup-\($0)") }
    for id in ids {
        _ = router.send(makeEnvelope(id), to: "peer-a")
    }
    check(mesh.sendCount == 5, "five unique messages dispatched")

    // The oldest two IDs were evicted; re-sending the oldest dispatches again.
    _ = router.send(makeEnvelope(ids[0]), to: "peer-a")
    check(mesh.sendCount == 6, "oldest dedup entry evicted and re-dispatched")
}

// 20. Outbox is bounded.
do {
    let router = MessageRouter()
    let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)
    router.register(smp)
    router.maxOutboxEntries = 2

    for _ in 0..<5 {
        _ = router.send(makeEnvelope(), to: "peer-a")
    }
    check(router.parkedCount == 2, "outbox bounded to maxOutboxEntries")
}

if failures == 0 {
    print("ALL SMOKE TESTS PASSED")
} else {
    print("\(failures) SMOKE TEST(S) FAILED")
    exit(1)
}

final class LockBox {
    private let lock = NSLock()
    private var _value: Int
    init(value: Int) { _value = value }
    func increment() { lock.lock(); defer { lock.unlock() }; _value += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
}