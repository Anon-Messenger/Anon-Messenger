# Anon — Analysis of the Existing Codebases

This document captures what each upstream repository actually contains (verified against the
current `Anon-Messenger` forks), where its integration seams are, and how Anon will use it.
Inspect the repos directly:

- `simplex-chat` (fork of `simplex-chat/simplex-chat`, branch `stable`)
- `simplexmq` (fork of `simplex-chat/simplexmq`, branch `stable`)
- `bitchat` (fork of `permissionlesstech/bitchat`, branch `main`)
- `Telegram-iOS` (fork of `TelegramMessenger/Telegram-iOS`, branch `master`)

---

## 1. simplexmq (SimpleX Messaging Protocol)

**Language:** Haskell. **License:** AGPL-3.0. **Build:** cabal.

### What it is
A message broker for *unidirectional simplex queues*: an SMP server, an SMP client library, and
an SMP agent that turns a set of unidirectional queues into duplex connections. It also ships
XFTP (file transfer) and an XRCP remote-control protocol.

### Module map (what matters for Anon)

| Module | Role |
| --- | --- |
| `Simplex.Messaging.Transport` | The `Transport` typeclass + `ATransport` GADT. TLS-based today. |
| `Simplex.Messaging.Transport.Client` | `runTLSTransportClient`, `connectTCPClient`, `connectSocksClient`. |
| `Simplex.Messaging.Client` | SMP client (create queue, send, subscribe, ack). |
| `Simplex.Messaging.Agent` | SMP agent (duplex connections over multiple servers/queues). |
| `Simplex.Messaging.Crypto.Ratchet` | Double ratchet. |
| `Simplex.Messaging.Crypto.SNTRUP761` | Post-quantum KEM bindings. |
| `Simplex.Messaging.Crypto.BBS` | BBS+ signatures. |
| `Simplex.Messaging.Protocol` / `Protocol.Types` | Wire protocol (Redis-style, version-negotiated). |

### The critical integration seam for I2P
The SMP client **already supports SOCKS proxying**. In
`Simplex.Messaging.Transport.Client`:

- `runTransportClient` takes `Maybe SocksCredentials` and a `TransportHost`.
- `TransportHost` has constructors for IPv4, IPv6, onion hosts, and domain names.
- `connectTCP` branches to `connectSocksClient` when a socks proxy is configured.

`i2pd` exposes a **SOCKS proxy** (default `127.0.0.1:4447`). Therefore "SMP over I2P" is a
*configuration and provisioning* problem, not a protocol rewrite: point the SMP client at
an `.i2p` destination through i2pd's SOCKS proxy. The same onion-host support is how SimpleX
already talks to Tor onion servers.

### What Anon uses vs. leaves
- **Use (as protocol + philosophy, not linked code on mobile):** the no-identifier model, the
  connection-link/QR invitation format, the double ratchet + PQ KEM layering, and the SMP/XFTP
  wire design we reimplement in Kotlin/Swift.
- **Leave:** the Haskell server/agent monolith for the mobile runtime. The desktop reference
  remains upstream simplex-chat; Anon's mobile core is natively implemented.

---

## 2. simplex-chat (SimpleX Chat)

**Language:** Haskell core + **Kotlin Multiplatform** UI. **License:** AGPL-3.0.

### Key structural finding
The mobile app is **Compose Multiplatform (Kotlin)**, not Swift:

- `apps/multiplatform/` — Gradle KMP project with `common`, `android`, `ios`, `desktop`.
- `apps/multiplatform/common/src/commonMain/kotlin/chat/simplex/common/...`
  - `model/` → `ChatModel.kt`, `SimpleXAPI.kt` (the UI ↔ core binding).
  - `views/` → `chatlist/`, `chat/`, `contacts/`, `usersettings/`, `newchat/`, `onboarding/`.
- The Haskell core is exposed to the UI through a C ABI (`commonMain/cpp/…/simplex-api.c`)
  using JNI on Android and a C shim on iOS/desktop.

### Core API surface
- `src/Simplex/Chat/Controller.hs` (~1,883 lines) — the central chat controller; the command
  monad and response/event streams that drive the UI.
- `src/Simplex/Chat.hs` / `src/Simplex/Chat/Mobile.hs` — mobile/FFI entry points.

### What Anon takes from simplex-chat
1. **Identity & connection model (the heart):** users have no accounts. A contact is created
   from a one-time invitation link/QR that encodes queue addresses + key fingerprints.
   All metadata (who talks to whom) is split across independent servers/queues.
2. **E2EE layering:** end-to-end double ratchet between *clients*, independent of the transport.
3. **App features to reimplement:** disappearing messages, multi-profile/incognito mode,
   panic wipe semantics, folder/tag organization.

### What Anon does NOT take
- The Kotlin Compose UI itself (we want a Telegram-like Swift UI on iOS first).
- The Haskell core as a linked dependency (we reimplement the controller natively so the
  transport router and mesh can be first-class citizens — see the architecture doc).
- SimpleX's default clearnet/Tor-server deployment model; Anon *defaults to I2P*.

---

## 3. bitchat (Bluetooth mesh + Nostr)

**Language:** Swift (iOS/macOS). **License:** Public domain / Unlicense.
**Build:** Swift Package Manager (`Package.swift`), Xcode project.

### What it is
A decentralized messenger with a **dual transport architecture**: local BLE mesh for offline,
Nostr for internet reach. No accounts, no phone numbers, no central servers.

### The pieces Anon reuses directly (this is the big win)

| Piece | Path | What it provides |
| --- | --- | --- |
| `Transport` protocol | `bitchat/Services/Transport.swift` | Abstract transport contract: reachability, prompt delivery, send/receive, peer snapshots, event delegate. |
| `MessageRouter` | `bitchat/Services/MessageRouter.swift` | Multi-transport routing with outbox/courier/ack/dedup/retry logic. |
| BLE mesh engine | `bitchat/Services/BLE/*` | ~50 files: source routing, multi-hop relay, Noise encryption, fragmentation, store-and-forward. |
| Identity | `bitchat/Identity/IdentityModels.swift` | Three-layer identity (network / crypto / social). |
| Embedded Tor | `localPackages/Arti/` | `TorManager.swift`, `TorURLSession.swift`, Rust Arti wrapper — a working embedded anonymous router. |
| Courier / Gateway | `bitchat/Services/Courier`, `Services/Gateway` | Store-and-forward, bridge drop dedup, relay bridges. |
| Panic wipe | `bitchat/Services/…` | Triple-tap wipe, `PanicResettingTransport`. |
| Noise | `bitchat/Noise/` | Noise protocol implementation. |

### Critical caveat — persistent identifier
Bitchat's whitepaper and `IdentityModels.swift` explicitly state the **peer ID is stable**
(derived from the long-term Noise static key) and that a passive observer can track a device.
This **conflicts with Anon's "zero persistent user identifiers"** requirement.

**Anon's fix (a deliberate divergence from bitchat):**
- Anonymous, *ephemeral, rotating* mesh identities per contact session — not a stable on-air ID.
- Contact discovery is via one-time SimpleX-style invitation, exchanged face-to-face (QR / NFC),
  **not** via signed public announces carrying a fixed ID.
- Public "channel" announce use a per-channel unlinkable subscription model (see architecture).

### What Anon leaves
- Nostr as the default internet transport. In Anon, **SMP over I2P is primary**; Nostr-over-I2P
  is an optional fallback for public/location-style channels, not the default private path.
- Bitchat's geohash location channels are reworked to run over I2P relays, not clearnet relays.

---

## 4. Telegram-iOS

**Language:** Swift (Bazel build, generated Xcode project). **License:** GPL-2.0(+).
**Couplings:** TDLib (`third-party/td`), a custom `mtproto-engine`, heavy cloud identity.

### What it is
The official Telegram client: an enormous, highly-coupled codebase built with Bazel, depending on
TDLib and MTProto and a Telegram account/cloud model. The UI is split across ~200 `submodules/*UI`
frameworks (e.g. `ChatListUI`, `ChatMessageBackground`, `ItemListUI`, `AsyncDisplayKit` fork).

### Why Anon does NOT link or port any of it
1. **Cloud identity is baked in.** Telegram's model (phone numbers, server-side accounts, MTProto
   sessions) is the opposite of Anon's no-identifier model. Stripping it out is more work than
   building a native UI against a clean controller.
2. **Build system entanglement.** Bazel + generated Xcode project + codesigning + TDLib/MTProto.
   Not a clean foundation for a fresh engine.
3. **License.** GPL (copyfree-unfriendly combination with bitchat's Unlicense; adds TDLib).

### What Anon takes from Telegram-iOS
- **Concrete design tokens (clean-room, factual values only).** Telegram-iOS is ~49% Swift, and
  the bulk of that is the presentation/UI layer, not core networking. Anon mines it for *facts*
  — canonical color values and the peer-name palette — and re-expresses them as original code:
  - `defaultDayAccentColor` → `0x0088ff` accent
  - chat-list day palette → title `0x000000`, message/preview `0x8e8e93`, free/secondary
    `0x6d6d72`, pinned-item background `0xf7f7f7`
  - peer-name color palette (7 canonical hues) from `ManagedPeerColorUpdates.swift`
  These live in `App/Anon/Sources/TelegramDesignTokens.swift`. Only uncopyrightable factual
  values are ported; **no Telegram Swift code is copied** (Telegram-iOS is GPL, Anon is AGPL, so
  the implementation stays clean-room). Layout semantics (chat-list rows, bubble shapes, search
  pill, composer) are reproduced as an original interpretation, not linked source.

---

## 5. What this means for the architecture (the decisive conclusion)

| Concern | Decision |
| --- | --- |
| Platform to start | **iOS, native Swift** — bitchat gives us the mesh + router + Tor for free; Telegram-iOS is a same-language visual reference. |
| Identity model | **SimpleX philosophy** (no identifiers, one-time invitations) on top of a **rotating, non-linkable mesh identity** (fixing bitchat's tracking defect). |
| Transport spine | Reuse/extend **bitchat's `Transport` + `MessageRouter`**, add an **SMP-over-I2P transport** and an **embedded i2pd** alongside embedded Tor. |
| Internet routing | **I2P by default**, Tor fallback optional, clearnet opt-in only for emergency/debug. |
| E2EE | **Double ratchet** (as in simplexmq) end-to-end over all transports, plus post-quantum KEM key agreement. |
| UI | Native Swift, Telegram-inspired, driven by a clean `ChatController`/`MessageRouter` API. |