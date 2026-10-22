# Anon — Implementation Milestones (M0–M3)

The first four milestones produce a working end-to-end prototype:

- **M0 — Foundation & anonymous network layer:** the skeleton app, i2pd/Tor hosting, the transport
  contract, and the multi-transport router (no UI polish, no SMP yet).
- **M1 — Offline path (BLE mesh):** messages exchange fully offline via Bluetooth mesh over the
  router, using an ephemeral mesh identity that fixes bitchat's stable-ID defect.
- **M2 — Internet path (SMP over I2P):** contacts established by one-time invitations, messages
  exchanged over SMP queues reached through I2P, with double-ratchet E2EE.
- **M3 — Telegram-style UI + MVP features:** the polished UI and the remaining MVP features
  (groups, files, disappearing messages, panic wipe, multi-profile/incognito).

Each milestone has **definition of done** criteria. The router is built *before* the SMP transport
so the offline path and the internet path can be demoted/verified independently.

---

## M0 — Foundation & anonymous network layer

**Goal:** prove the three bottom layers of the architecture work on-device and behind a clean
router API.

### Scope
1. Scaffold the Anon iOS app (Swift Package Manager + minimal Xcode app target).
2. Vendor/extract the reusable bitchat packages:
   - BLE mesh engine (`Services/BLE/*`, `Noise/`)
   - `Transport`/`MessageRouter` (§5 of the architecture)
   - `BitFoundation`, `BitLogger`, and their test mocks
   as local Swift packages under `Packages/` (Unlicense, attribution preserved).
3. Define and freeze the versioned interfaces:
   - `AnonTransport`, `TransportPriority`, `Envelope`, `DeliveryAck`
   - `AnonymousRouter`
4. Embed **i2pd** (C++ core behind FFI) and keep the **Arti/Tor** wrapper from bitchat. Both expose
   the same `AnonymousRouter` protocol.
5. Implement the router core (registry, reachability, outbox, ack/dedup, retry) with the mesh
   transport registered but initially a no-op pass-through.
6. Logging hooks so every envelope transition (queued → delivered → acked) is observable in tests.

### Definition of done
- App launches and starts/boots i2pd in `off`→`booting`→`ready` states (visible in a debug screen).
- Tor (Arti) starts on demand.
- Router unit tests (mock transports) prove priority selection, ack/dedup, retry, and courier
  fallback decisions.
- No identifiable data leaves the device during M0 (verified by the tests).

---

## M1 — Offline path: BLE mesh messaging

**Goal:** two devices exchange messages with **no internet**, demonstrating the mesh transport
through the router.

### Scope
1. Port the BLE mesh engine to the `AnonTransport` contract (replace bitchat's channel-centric
   entry points with the router's envelope send/receive).
2. **Replace the mesh identity model** with the ephemeral, rotating identity from §2.3:
   - no stable on-air peer ID;
   - contact sessions pinned by the invitation's long-term ratchet key (for M1, pinned via an
     in-memory fixture, since full invitations land in M2).
3. Integrate the double-ratchet layer (inner) so mesh payloads are ratchet ciphertext, not just
   Noise-layer ciphertext.
4. Basic one-to-one message flow: compose → envelope → router → mesh → ack → display.
5. Basic store-and-forward courier path: device C (in range of A, out of range of B) carries a
   sealed envelope from A to B.

### Definition of done
- Two devices message each other over BLE with airplane mode enabled (verified in a lab test).
- A third device relays a message between two non-adjacent devices (multi-hop).
- Radio capture/unit tests confirm **no stable identifier** is observable across sessions.
- Message content is ratchet-encrypted end-to-end over the mesh.

---

## M2 — Internet path: SMP over I2P

**Goal:** contacts established by one-time invitations; messages exchanged over SMP queues reached
through I2P. This is the milestone that makes Anon feel like "SimpleX + I2P".

### Scope
1. Implement a native Swift **SMP client** (Redis-style, version-negotiated wire protocol) targeting
   SMP relays hosted as `.i2p` destinations.
2. Dial relays through the `AnonymousRouter` SOCKS interface (i2pd `127.0.0.1:4447`); support the
   same configuration for Tor onion relays as a fallback.
3. Implement **one-time invitations / QR codes** (`anon://connection?...&v=1`) carrying:
   - queue addresses,
   - long-term ratchet public keys (+ fingerprints),
   - one-time ephemeral handshake key.
4. Integrate **post-quantum bootstrap** (X25519 + sntrup761 hybrid KEM) for initial session setup.
5. Register `SMPOverI2PTransport` with the router so the router's priority becomes
   **Mesh → SMP-over-I2P**; verify automatic failover between the two.
6. Stand up a reference **SMP relay over I2P** (upstream `simplexmq` smp-server behind i2pd) for
   the test environment.

### Definition of done
- User A scans user B's QR invitation and the connection completes end-to-end over I2P.
- Messages flow A→B over SMP queues when devices are far apart (not in mesh range).
- Failover is verified: bring devices into mesh range and the router prefers mesh; separate them
  and it transparently falls back to SMP-over-I2P without re-sending duplicates.
- No username/phone/stable ID exists anywhere on the SMP/I2P relays.

---

## M3 — Telegram-style UI + MVP features

**Goal:** wrap the working engine in the Telegram-inspired UI and complete the remaining MVP
features.

### Scope (as the engine's features complete, not before)
1. **Telegram-like UI shell:** chat-list view, chat view (bubble + composer), media handling,
   folders, themes (light/dark), swipe actions — all bound to the `ChatController` API.
2. **Basic groups** (mesh gossip + SMP group queue topologies, encrypted by a group ratchet).
3. **File/image sharing** with mesh-appropriate size limits (transfer policies capped; larger
   files deferred to XFTP over I2P post-MVP).
4. **Disappearing messages** (TTL honored in store + envelope retention).
5. **Panic / emergency wipe** (quiesce mesh + router, destroy store; gesture + explicit control).
6. **Multi-profile / incognito mode** per §2.4.

### Definition of done (prototype)
- A walkthrough demo:
  1. Create local profile (no identifiers).
  2. Scan a QR to add a contact.
  3. Send/receive offline via mesh.
  4. Send/receive over the internet via SMP-over-I2P.
  5. Toggle disappearing messages; trigger panic wipe.
- UI presents a Telegram-like chat list and chat view; the privacy/network state is visible
  (Battery/i2pd status) without leaking identifiers.

---

## Milestone sequencing rationale

- **M0 before M1** — freeze the seams (transport + router + network layer) so all later work is
  modular and independently testable.
- **M1 before M2** — the mesh path reuses the most proven code (bitchat) and derisks the identity
  change early; SMP-over-I2P is the larger net-new implementation and builds on the router that M0
  proved.
- **M2 before M3** — the internet path is the higher-risk privacy requirement; the UI is polish on
  top and must not gate the functioning end-to-end path.