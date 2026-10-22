# Anon — Technical Architecture

## 0. Goals and non-negotiables

Anon is a hybrid anonymous messenger. The architecture encodes these priorities in order:

1. **Privacy and anonymity > convenience.** No persistent user identifiers of any kind; metadata
   about who talks to whom must be extremely hard to observe.
2. **Offline is first-class.** Bluetooth LE mesh is a transport on equal footing with SMP-over-I2P,
   not a fallback afterthought.
3. **I2P is the default internet path.** All internet traffic goes through I2P by default; Tor is
   an optional fallback; clearnet is opt-in for emergency/debug only.
4. **Modular transports.** Individual transports can be improved, swapped, or removed independently.

---

## 1. Layering

The system is split into four layers with **one-way dependencies** (upper layers depend on lower
ones, never the reverse):

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI Layer (SwiftUI / native Swift, Telegram-inspired)               │
│  ChatListView · ChatView · Composer · Media · Folders · Themes      │
└───────────────────────────────┬─────────────────────────────────────┘
                                │  ChatController API (async commands + event stream)
┌───────────────────────────────▼─────────────────────────────────────┐
│  Chat / Identity Controller                                         │
│  Profiles · Contacts · Groups · E2EE session mgmt · DB · Expiry     │
│  Invitations (QR/link) · Disappearing msgs · Panic wipe · Incognito │
└───────────────────────────────┬─────────────────────────────────────┘
                                │  outbox.enqueue(recipient, envelope)
┌───────────────────────────────▼─────────────────────────────────────┐
│  Multi-Transport Message Router                                     │
│  Transport registry · reachability · priority · ack/dedup · retry   │
│  Courier store-and-forward · bridge drops                           │
└───────┬──────────────┬────────────────┬─────────────┬───────────────┘
        │              │                │             │
┌───────▼──────┐ ┌─────▼──────┐ ┌───────▼────────┐ ┌──▼───────────────┐
│ BLE Mesh     │ │ SMP over   │ │ Nostr over I2P │ │ (future) XFTP    │
│ Transport    │ │ I2P        │ │ Transport      │ │ over I2P         │
│ (offline)    │ │ Transport  │ │ (public chans) │ │ (file transfer)  │
└───────┬──────┘ └─────┬──────┘ └───────┬────────┘ └──┬───────────────┘
        │              │                │             │
┌───────▼──────────────▼────────────────▼─────────────▼───────────────┐
│  Anonymous Network Layer (embedded)                                 │
│  i2pd (I2P router)  ·  Arti (Tor router, optional)  ·  SOCKS shim   │
└─────────────────────────────────────────────────────────────────────┘
```

- **UI Layer** — pure presentation. No crypto, no sockets, no identity keys. Talks only to the
  `ChatController`.
- **Chat / Identity Controller** — the source of truth. Owns profile/contact/groups state, the
  double-ratchet sessions, invitation parsing, expiration, panic wipe, and the local store.
- **Multi-Transport Message Router** — the "one envelope, many ways to deliver it" layer. It knows
  nothing about message *content*, only envelopes and delivery.
- **Transport Layer** — concrete `Transport` implementations (mesh, SMP-over-I2P, Nostr-over-I2P).
- **Anonymous Network Layer** — the embedded i2pd router (and optional Arti/Tor) exposing a SOCKS
  interface and managing `.i2p` destinations.

The layering mirrors bitchat's proven `Transport` / `MessageRouter` split, with a SimpleX-style
identity controller inserted above the router instead of bitchat's channel-centric model.

---

## 2. Identity & privacy model

### 2.1 Zero persistent identifiers (the SimpleX inheritance)

There is **no account, no phone number, no username, no long-term cryptographic ID visible to any
server or relay**. A user is a set of local profiles on a device. A "contact" is a relationship
established by **a one-time invitation link / QR code**, exactly as in SimpleX:

```
anon://connection?smp=...&v=1&e2e=...   (short, QR-encoded)
```

The invitation contains:
- the recipient's SMP queue address(es) on one or more SMP relays reached over I2P;
- the recipient's long-term encryption/ratchet public keys and a fingerprint of them;
- a one-time ephemeral key for the initial handshake.

Anyone who lacks this invitation cannot address you. There is nothing global to look you up by.

### 2.2 Metadata protection

- **Unidirectional queues.** Each contact direction uses separate SMP queues, on **separate
  I2P-hosted SMP relays**. A relay sees only one side of a conversation and cannot link senders to
  recipients.
- **Rotation.** Queue addresses and mesh session keys rotate. A long-lived contact relationship is
  a local label only.
- **Anonymous network layer.** I2P hides source/destination IP correlation. The SMP relays see
  `.i2p` clients, not real addresses.
- **No server-side contact graph.** Nothing that could enumerate a user's contacts is ever uploaded.

### 2.3 Mesh identity — the divergence from bitchat

Bitchat uses a **stable on-air ID derived from the Noise static key**, which its own whitepaper
admits is trackable by a passive radio observer. Anon **rejects** that:

- **Anonymous, short-lived mesh identities.** Each contact session gets an ephemeral Noise identity
  that rotates independently of any long-term identifier.
- **Invitation-pinned keys.** The long-term ratchet key that a mesh contact trusts is pinned via the
  one-time invitation (fingerprint/QR), so the on-air Noise identity never needs to be stable.
- **No public signed announces carrying a fixed ID.** Public channels use a per-channel
  *unlinkable subscription* (a blinded channel key), not a device identity.

Result: a nearby radio observer sees rotating, unlinkable sessions; they cannot track a device or
recover "who is who" beyond what the invitation already established privately.

### 2.4 Profiles, incognito, and panic wipe

- **Multi-profile:** multiple independent profiles coexist; each has its own identifier set and
  contact graph, never mixed.
- **Incognito mode:** a profile can be used without any persistence (memory-only store), or with an
  ephemeral identity per conversation.
- **Panic / emergency wipe:** a gesture (triple-tap as in bitchat, plus an explicit button) destroys
  identities, ratchet state, queues, and store; mesh radio and network layer are quiesced first
  (bitchat's `PanicResettingTransport` pattern).

---

## 3. Encryption

Two nested layers, matching the "double ratchet + additional layer preferred" requirement:

1. **Double ratchet per contact (inner).** Alice ↔ Bob sessions use a double ratchet (as in
   simplexmq's `Crypto/Ratchet.hs`). Each contact direction has its own session. This gives forward
   secrecy and post-compromise security **regardless of transport**.
2. **Post-quantum key agreement (bootstrap).** Initial session setup uses a hybrid KEM
   (X25519 + a post-quantum KEM such as sntrup761, mirroring simplexmq) so an invitation captured
   today cannot be decrypted later by a quantum adversary.
3. **Transport-layer encryption (outer).**
   - Mesh: **Noise protocol** sessions (bitchat's existing implementation), with forward secrecy for
     live sessions and sealed envelopes for store-and-forward.
   - SMP-over-I2P: the SMP channel is additionally wrapped in I2P's garlic routing; the content is
     already ratchet-encrypted end-to-end.

### 3.1 Hardened AEAD conventions (implemented in `AnonCrypto`)

The current `SessionCipher` already goes beyond a single shared key, closing two
classic weaknesses before the full double ratchet lands:

- **Directional keys (reflection resistance).** A→B and B→A keys are derived
  independently via HKDF over the *ordered* public-key pair, so a ciphertext
  cannot be reflected back to its sender and still authenticate.
- **Session binding (key-substitution resistance).** Every AES-GCM tag is bound
  to the canonical `(PeerA, PeerB)` session identity as associated data, so a
  valid ciphertext cannot be transplanted into another session.
- **Replay/expiry.** Envelopes carry a TTL; the router drops already-expired or
  queued-and-expired envelopes, and both the dedup set and the outbox are
  bounded to prevent memory exhaustion.

Envelope layout (stored/delivered by the router):

```
envelope = {
  magic, version,
  recipient_ref (local opaque, not a network ID),
  transport_hint,               // mesh | smp_i2p | nostr_i2p
  sealed_payload,               // ratchet ciphertext (content + message ID + timestamp)
  message_id, ttl,
}
```

The router never sees plaintext. The controller handles sealed-payload encrypt/decrypt.

---

## 4. Transports (priority order)

The `MessageRouter` maintains a priority-ordered set of `Transport` instances:

1. **BLE Mesh** — offline, multi-hop, lowest latency when peers are nearby.
2. **SMP over I2P** — the primary internet path; asynchronous, store-and-forward, no identifiers.
3. **Nostr over I2P** — optional fallback for public/location channels (not the default private path).

### 4.1 BLE mesh transport

Reused from bitchat (`Services/BLE/*`) with the identity model from §2.3 substituted. Key
properties kept:

- Multi-hop source routing (≤ N hops), fragmented transfer, Noise encryption, automatic discovery,
  adaptive duty cycling.
- Store-and-forward couriers: a connected, trusted peer can carry a sealed envelope to a
  disconnected peer (bitchat's courier/gateway model).
- File transfer via fragmentation; mesh file size limits are conservative (transfer-policy
  capped) — see MVP.

### 4.2 SMP over I2P transport

A native Swift implementation of the SMP client protocol, with the same wire format as simplexmq
so Anon can interoperate with upstream SMP servers (AGPL-licensed servers are *deployed*, not
linked). Two facts make this low-risk:

- The SMP wire protocol is Redis-style and version-negotiated (simplexmq's
  `Messaging/Protocol.hs`).
- The network hop is SOCKS-friendly: i2pd provides a SOCKS proxy; the SMP client simply resolves
  the relay's `.i2p` destination through it (the precise seam simplexmq already exposes via
  `runTransportClient` / `connectSocksClient`).

### 4.3 Nostr over I2P transport (optional)

Bitchat already treats Nostr as a relay transport (its private-envelope scheme is app-specific, not
NIP-17/44/59). In Anon this transport is **opt-in** and **only** used for public/location-style
channels over **I2P-hosted relays**, never as the default private message path.

---

## 5. The Multi-Transport Message Router

This is the heart of the system. It generalizes bitchat's `MessageRouter` and removes its
channel-centric assumptions.

### 5.1 Transport contract

```swift
protocol AnonTransport: AnyObject {
    var transportID: TransportID { get }            // .mesh, .smpI2P, .nostrI2P
    var reachability: TransportReachability { get } // .available / .degraded / .unavailable

    func isPeerReachable(_ ref: PeerRef) -> Bool
    func canDeliverPromptly(to ref: PeerRef) -> Bool
    func send(_ envelope: Envelope, to ref: PeerRef, completion: @escaping (DeliveryAck) -> Void)
    func registerReceiveHandler(_ handler: @escaping (Envelope) -> Void)
}

enum TransportPriority: Int, Comparable {
    case mesh = 0        // preferred when peers are nearby
    case smpI2P = 1      // primary internet path
    case nostrI2P = 2    // fallback for public channels
}
```

### 5.2 Routing algorithm

For each outgoing envelope:

1. **Resolve recipient ref** into the set of transports the controller says are available for that
   contact (a contact may be mesh-only, SMP-only, or both).
2. **Select by priority + reachability:**

   ```
   candidates = transports
     .filter { $0.isPeerReachable(ref) }
     .filter { $0.canDeliverPromptly(to: ref) }
     .sorted { $0.priority < $1.priority }

   if candidates includes .mesh:        deliver via mesh
   else if candidates includes .smpI2P: deliver via SMP-over-I2P
   else if candidates includes .nostrI2P (public): deliver via Nostr-over-I2P
   else: queue for courier / late delivery
   ```

3. **Ack & dedup.** Every envelope carries a `message_id`. The router tracks acks per
   `(recipient, message_id)`, dedups on receipt, and retries with backoff when a higher-priority
   transport becomes available. (bitchat's outbox/ack/dedup machinery is reused.)
4. **Courier fallback.** When *no* transport can reach a recipient, a sealed envelope may be handed
   to a trusted connected peer who physically carries it (mesh store-and-forward), and/or parked on
   an I2P bridge drop, both with TTL + attempt caps. Receivers dedup by `message_id`.

This delivers the required behavior: **Mesh → SMP-over-I2P → Nostr fallback**, transparently.

---

## 6. Anonymous network layer (i2pd embedding)

Bitchat already embeds **Arti (Tor)** as a managed in-process router
(`localPackages/Arti/TorManager.swift`, `TorURLSession.swift`). Anon does the same for **i2pd**:

- **Embedded i2pd build.** Ship i2pd as a library (C++ core) behind an FFI; Anon starts it as part
  of the app and monitors tunnel state.
- **SOCKS interface.** i2pd's SOCKS proxy (`127.0.0.1:4447`) is the seam every internet transport
  (SMP client, Nostr client) uses; a thin `AnonSocksTransport` wraps URLSession/sockets to dial
  `.i2p` destinations.
- **Companion-app mode.** On platforms where embedding is constrained, Anon supports an external
  i2pd app/daemon as an equivalent backend (the "excellent companion app support" requirement),
  selected in settings.
- **Tor fallback.** The embedded Arti router remains available for Tor-onion destinations, behind
  the same SOCKS abstraction, so transports are network-agnostic.

```swift
protocol AnonymousRouter {
    var kind: RouterKind { get }            // .i2p | .tor
    var socksProxy: SocksEndpoint { get }
    var status: RouterStatus { get }        // .booting/.ready/.degraded/.off
    func start() async throws
    func stop() async
}
```

Transport code depends on `AnonymousRouter`, never on a specific router.

---

## 7. Data store

- **Local-first**, encrypted at rest (SQLite with SQLCipher or an encrypted store comparable to
  bitchat's stores and SimpleX's SQLite store).
- Tables: profiles, contacts (local labels + invitation-pinned keys + queue refs), conversations,
  messages (with TTL for disappearing messages), outbox, transport state.
- **Nothing identifying leaves the device unless the user shares an invitation.**

---

## 8. Platform decision (first prototype = iOS / native Swift)

| Criterion | iOS (Swift) result |
| --- | --- |
| BLE mesh + router + Tor | Reuse from bitchat (Unlicense) nearly 1:1 |
| Design reference | Telegram-iOS is Swift — direct visual spec |
| Embedded router experience | Arti already integrated in bitchat; i2pd ships iOS/tvOS targets |
| Licensing | Unlicense (bitchat) + BSD-3 (i2pd) + AGPL (Anon) mix cleanly |
| Offline mesh capability | iOS CoreBluetooth + i2pd on-device |

Android is second (Kotlin), reusing the transport/router *protocols* and the design spec, with the
Android BLE stack; the SIMP protocol client and router logic are written to be portable.

---

## 9. Threat model (summary)

| Adversary | What they can observe | Anon defense |
| --- | --- | --- |
| Passive radio listener (BLE) | Rotating Noise sessions, no stable ID | Ephemeral mesh identities |
| SMP/I2P relay operator | One side of one queue, no IP, no contact graph | Unidirectional queues + I2P + rotation |
| ISP / network observer | I2P tunnel traffic only, no plaintext metadata | Default I2P, clearnet opt-in only |
| Seized / lost device | At-rest store | Encrypted store + panic wipe + disappearing msgs |
| Quantum retroactive decrypt | Invitations captured today | Hybrid PQ KEM (X25519 + sntrup761) |

---

## 10. Key interfaces (stability contract)

These are the seams that must stay stable so transports can be improved independently:

1. `AnonTransport` / `TransportPriority` / `AnonymousRouter` (§5.1, §6) — adding a transport or
   router never touches the controller.
2. `ChatController` command/event API (§1) — the UI never touches transport state.
3. Envelope format (§4) — versioned (`magic`, `version`) for forward compatibility.
4. Invitation format (§2.1) — versioned (`v=1`) and self-describing.