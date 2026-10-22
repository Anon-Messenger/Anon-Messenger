# Anon — Post-MVP Roadmap

Features are grouped by the order they unlock further value. Each block lists the dependency it
builds on and the transport/architecture notes. Priority deliberately follows
**privacy > offline capability > convenience**.

---

## Phase A — Fill out the MVP privacy surface (immediately after M3)

| Feature | Notes / dependency |
| --- | --- |
| **XFTP file transfer over I2P** | Large files; chunked transfer over `.i2p` destinations (mirrors simplexmq XFTP). Depends on M2 SOCKS seam. |
| **Queue/relay rotation UX** | Automatic rotation of SMP queues and mesh session keys as a privacy default. |
| **Key/material verification** | Show ratchet fingerprint QR for out-of-band verification per contact. |
| **Relay trust selection** | Let profiles pin/choose I2P SMP relays (and Tor onion relays) explicitly. |
| **Notification privacy** | Push notifications without leaking identifiers (I2P-resident notification relay; blinded tokens). |

---

## Phase B — Real-time media (calls)

| Feature | Notes / dependency |
| --- | --- |
| **Voice calls (1:1)** | WebRTC data/audio channel established via the same double-ratchet + invitation model. |
| **Calls over I2P (degraded)** | I2P latency is high; prioritize mesh for calls, SMP/I2P signaling, peer-to-peer when reachable. |
| **Calls over mesh** | Low-latency for proximate devices; opportunistic direct audio. |
| **Group calls** | Requires group ratchet + selective forwarding for a mesh/SMP hybrid topology. |

Calling uses the *same* contact/invitation relationship — no new identifiers are introduced.

---

## Phase C — Better groups & communities

| Feature | Notes / dependency |
| --- | --- |
| **Large public channels** | Unlinkable per-channel subscriptions over I2P-hosted Nostr/SMP relays (blinded keys from §2.3). |
| **Group roles / moderation** | Local reputation + blinded membership credentials (BBS+ signatures, mirroring simplexmq's BBS work). |
| **Forward secrecy for groups** | Group ratchet (MLS-style) replacing shared symmetric keys. |
| **Location/geohash channels** | Reimplement bitchat's geohash model over I2P relays, not clearnet. |

---

## Phase D — Multi-device & continuity

| Feature | Notes / dependency |
| --- | --- |
| **Multi-device pairing** | Pair a secondary device via one-time invitation; share connection state locally (adversarial to "single device" privacy model — optional, clearly labeled). |
| **Backup & restore** | Encrypted export/import by invitation QR; no cloud by default. |
| **Desktop (macOS first)** | Reuse the Swift packages; the router/controller are platform-agnostic; macOS runs the same i2pd/Tor embedding. |
| **Android** | Kotlin port of the `AnonTransport` + router + SMP client + i2pd (JNI) against the Android BLE stack. |

---

## Phase E — UX / convenience (where privacy allows)

| Feature | Notes / dependency |
| --- | --- |
| **Themes / folders / pinned chats** | Pure UI; already scoped in M3. |
| **Message reactions, replies, edits** | Local metadata only; ratchet-encrypted. |
| **Stickers / GIFs (offline-safe)** | Media pipeline already handles sized files over mesh/I2P. |
| **Bots / services** | SimpleX-style "service protocol" over SMP; services cannot enumerate users (no identifiers). |
| **Translation / accessibility** | UI-local; no cloud calls (local model or opt-in only). |

---

## Explicitly deferred / non-goals

| Item | Why deferred or rejected |
| --- | --- |
| Clearnet default transport | Rejected: contradicts "I2P by default". Clearnet remains opt-in emergency/debug. |
| Phone-number / username lookup | Rejected: violates the zero-identifier model. |
| Server-side account/sync | Rejected: client-local identity only; multi-device is invitation-based. |
| Full NIP-17/44/59 interoperability | Deferred: Nostr is an optional public-channel transport, not the privacy path. |

---

## Milestones beyond M3 (proposed numbering)

- **M4 — XFTP over I2P + relay/queue rotation.**
- **M5 — Voice over mesh/I2P (1:1).**
- **M6 — Public channels (unlinkable subscriptions).**
- **M7 — Multi-device pairing + encrypted backup.**
- **M8 — Android alpha.**
- **M9 — Group ratchet (MLS-style) + group calls.**