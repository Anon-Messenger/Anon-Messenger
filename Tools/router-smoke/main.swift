import Foundation
import AnonCore
import AnonRouter
import AnonTransports

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