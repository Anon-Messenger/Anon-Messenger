import XCTest
@testable import AnonCore
@testable import AnonRouter
@testable import AnonTransports

final class MessageRouterTests: XCTestCase {

    private func makeEnvelope(
        id: MessageID = .random(),
        to ref: PeerRef = "peer-a",
        payload: Data = Data([0x01, 0x02, 0x03])
    ) -> Envelope {
        Envelope(
            recipientRef: ref,
            sealedPayload: payload,
            messageID: id
        )
    }

    // MARK: - Priority selection

    func testMeshIsPreferredWhenReachable() {
        let router = MessageRouter()
        let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)
        let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P)
        let nostr = InMemoryTransport(transportID: .nostrI2P, priority: .nostrI2P)

        [mesh, smp, nostr].forEach(router.register)

        let decision = router.send(makeEnvelope(), to: "peer-a")

        XCTAssertEqual(decision.chosenTransport, .mesh)
        XCTAssertEqual(mesh.sendCount, 1)
        XCTAssertEqual(smp.sendCount, 0)
        XCTAssertEqual(nostr.sendCount, 0)
        XCTAssertFalse(decision.queuedForCourier)
    }

    func testSMPIsChosenWhenMeshCannotReachPeer() {
        let router = MessageRouter()
        let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh, reachesAllPeers: false)
        let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P)

        [mesh, smp].forEach(router.register)

        let decision = router.send(makeEnvelope(), to: "peer-a")

        XCTAssertEqual(decision.chosenTransport, .smpI2P)
        XCTAssertEqual(mesh.sendCount, 0)
        XCTAssertEqual(smp.sendCount, 1)
    }

    func testUnavailableTransportIsNeverChosen() {
        let router = MessageRouter()
        let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh, reachability: .unavailable)
        let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P)

        [mesh, smp].forEach(router.register)

        let decision = router.send(makeEnvelope(), to: "peer-a")

        XCTAssertEqual(decision.chosenTransport, .smpI2P)
        XCTAssertEqual(mesh.sendCount, 0)
    }

    // MARK: - Courier parking & retry

    func testReachableButNotPromptParksForCourier() {
        let router = MessageRouter()
        let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)

        router.register(smp)

        let envelope = makeEnvelope()
        let decision = router.send(envelope, to: "peer-a")

        XCTAssertNil(decision.chosenTransport)
        XCTAssertTrue(decision.queuedForCourier)
        XCTAssertEqual(router.parkedCount, 1)
        XCTAssertEqual(smp.sendCount, 0)
    }

    func testRetryParkedDispatchesWhenTransportBecomesPrompt() {
        let router = MessageRouter()
        let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, promptDelivery: false)

        router.register(smp)

        let envelope = makeEnvelope()
        router.send(envelope, to: "peer-a")
        XCTAssertEqual(router.parkedCount, 1)

        smp.promptDelivery = true
        router.retryParked()

        XCTAssertEqual(router.parkedCount, 0)
        XCTAssertEqual(smp.sendCount, 1)
    }

    func testUnreachableTransportDoesNotPark() {
        let router = MessageRouter()
        let smp = InMemoryTransport(transportID: .smpI2P, priority: .smpI2P, reachesAllPeers: false)

        router.register(smp)

        let decision = router.send(makeEnvelope(), to: "peer-a")

        XCTAssertNil(decision.chosenTransport)
        XCTAssertFalse(decision.queuedForCourier)
        XCTAssertEqual(router.parkedCount, 0)
    }

    // MARK: - Deduplication

    func testDuplicateSendIsSuppressed() {
        let router = MessageRouter()
        let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)

        router.register(mesh)

        let id = MessageID("fixed-id")
        let first = router.send(makeEnvelope(id: id), to: "peer-a")
        let second = router.send(makeEnvelope(id: id), to: "peer-a")

        XCTAssertEqual(first.chosenTransport, .mesh)
        XCTAssertNil(second.chosenTransport)
        XCTAssertFalse(second.queuedForCourier)
        XCTAssertEqual(mesh.sendCount, 1)
    }

    func testInboundEnvelopeIsDeduplicated() {
        let router = MessageRouter()
        let mesh = InMemoryTransport(transportID: .mesh, priority: .mesh)
        router.register(mesh)

        let received = expectation(description: "received once")
        received.expectedFulfillmentCount = 1
        received.assertForOverFulfill = true

        router.onReceive { _ in received.fulfill() }

        let envelope = makeEnvelope(id: MessageID("inbound-id"))
        mesh.deliverInbound(envelope)
        mesh.deliverInbound(envelope)

        wait(for: [received], timeout: 1.0)
    }
}