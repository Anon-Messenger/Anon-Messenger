# Anon — Build Instructions & Development Setup

## 0. Toolchain requirements

| Tool | Minimum | Notes |
| --- | --- | --- |
| macOS | 14+ (Ventura or newer) | iOS development + simulator |
| Xcode | 15+ | Swift 5.9+ toolchain |
| Swift Package Manager | bundled with Xcode | primary dependency management |
| CMake | 3.24+ | building i2pd C++ core |
| Rust | stable (1.75+) | building the optional Arti/Tor packages |
| Python | 3.9+ | build scripts (FFI generation, i2pd build) |
| Graphviz (optional) | any | rendering architecture diagrams |

The iOS **simulator** is sufficient for M0–M3 networking tests; physical devices are required for
real Bluetooth mesh validation (mesh does not work between simulators).

---

## 1. Repository layout (target)

The actual source tree starts landing during M0. Planned layout:

```
Anon-Messenger/                     # this repo
├── README.md
├── LICENSE
├── docs/                           # architecture + milestones + roadmap (this phase)
├── App/                            # Anon iOS app (SwiftUI)
│   ├── Sources/
│   │   ├── UI/                     # Telegram-inspired views
│   │   ├── Controller/             # Chat/Identity Controller
│   │   └── Resources/
│   └── Anon.xcodeproj (generated)  # thin wrapper over the Package below
├── Packages/
│   ├── AnonCore/                   # controller, ratchet, invitation codec
│   │   ├── Package.swift
│   │   └── Sources/...
│   ├── AnonRouter/                 # Multi-Transport Message Router + Transport contract
│   ├── AnonTransports/
│   │   ├── Mesh/                   # bitchat-derived BLE mesh
│   │   ├── SMP/                    # SMP-over-I2P client
│   │   └── Nostr/                  # Nostr-over-I2P (post-MVP)
│   └── AnonNetwork/
│       ├── I2P/                    # i2pd FFI wrapper
│       └── Tor/                    # Arti wrapper (bitchat-derived)
├── third_party/
│   ├── bitchat/                    # extracted (Unlicense) or git submodule
│   └── i2pd/                       # git submodule (BSD-3)
├── infra/                          # reference relays (I2P-hosted SMP relay)
└── tools/                          # dev scripts
```

Derivation sources:
- `Packages/AnonTransports/Mesh` and `Packages/AnonNetwork/Tor` originate from
  `Anon-Messenger/bitchat` (Unlicense).
- `Packages/AnonTransports/SMP` implements the wire protocol documented in
  `Anon-Messenger/simplexmq` (`protocol/simplex-messaging.md`); SMP servers deployed from
  upstream `simplexmq` are used, not linked.
- `third_party/i2pd` is a submodule of `PurpleI2P/i2pd` (BSD-3-Clause).

---

## 2. Getting the sources

The four upstream forks are not nested by default; they are reference sources for extraction.

```sh
git clone https://github.com/Anon-Messenger/Anon-Messenger.git
cd Anon-Messenger

# Reference sources (used to extract/vendor packages, not built directly in place)
mkdir -p reference && cd reference
git clone --depth 1 --branch main   https://github.com/Anon-Messenger/bitchat.git
git clone --depth 1 --branch stable https://github.com/Anon-Messenger/simplexmq.git
git clone --depth 1 --branch stable https://github.com/Anon-Messenger/simplex-chat.git
# Telegram-iOS is large (~860 MB) — clone only when following its UI as a design reference:
# git clone --depth 1 https://github.com/Anon-Messenger/Telegram-iOS.git
```

> i2pd is added as a submodule during M0 once `App/` exists (see §4).

---

## 3. Building the reference dependencies

### 3.1 Bitchat (mesh + Tor reference — Swift package)

```sh
cd reference/bitchat
swift build            # builds the core packages (BitFoundation, Arti wrapper, BLE services)
swift test             # mesh/Noise/router tests must pass before extraction
```

The extracted packages keep their own test targets so regression tests travel with Anon.

### 3.2 i2pd (C++ core, for embedding)

```sh
cd third_party/i2pd
make -j"$(sysctl -n hw.ncpu)" USE_AESNI=no USE_AVX=no              # embedded iOS-style build
# OR via CMake when targeting specific architectures:
mkdir build && cd build && cmake -DCMAKE_BUILD_TYPE=Release .. && cmake --build .
```

For the iOS build, cross-compilation profiles are defined under `App/Sources/…/I2P/toolchains/`;
see the M0 notes in `tools/`.

### 3.3 Arti / Tor (optional fallback)

Reuse the bitchat package (`localPackages/Arti`), which wraps Arti via Rust FFI:

```sh
cd reference/bitchat/localPackages/Arti
cargo build --release --features apple --target aarch64-apple-ios
```

---

## 4. Building the Anon app (after M0 scaffolds `App/`)

```sh
# bootstrapping the FFI and i2pd core
make bootstrap         # runs: git submodule update --init third_party/i2pd && sh tools/build-i2pd.sh

# build + run in the iOS simulator
open packages/App/Anon.xcodeproj   # local Swift Package resolution is automatic
# Or CLI:
xcodebuild -scheme Anon -destination 'platform=iOS Simulator,name=iPhone 15' build
```

**Debug flags** available in the app:

- `ANON_TRANSPORT_LOG=1` — envelope transitions (queued → delivered → acked).
- `ANON_I2P_STATUS=1` — show i2pd router state onscreen.
- `ANON_FORCE_TRANSPORT=mesh|smp|nostr` — pin the router to one transport for deterministic tests.

---

## 5. Running a reference SMP relay over I2P (for M2)

```sh
# 1. Install/run i2pd on a host, generating an .i2p destination for the relay.
#    Anon's embedded router exposes the same SOCKS seam (127.0.0.1:4447).

# 2. Build the upstream SMP server (Haskell, from Anon-Messenger/simplexmq).
cd reference/simplexmq
cabal update && cabal build exe:smp-server

# 3. Point the server at an i2pd virtual destination and initialize.
#    (Documented in simplexmq README; initializing requires OpenSSL.)
cabal run smp-server -- init -n <relay-hostname>.i2p

# 4. Publish the .i2p destination so Anon clients can reach the relay.
```

Anon's SMP transport dials the relay through i2pd SOCKS exactly like upstream SimpleX's
`connectSocksClient` dials an onion host.

---

## 6. Testing strategy

| Layer | Test type | Command (post-M0) |
| --- | --- | --- |
| Router | unit (mock transports) | `swift test --filter AnonRouterTests` |
| Mesh | unit + integration | `swift test --filter MeshTransportTests` |
| Mesh | multi-device lab (2–3 iPhones, airplane mode) | manual + `tools/mesh-lab-runner.sh` |
| SMP | unit (wire protocol vectors) | `swift test --filter SMPProtocolTests` |
| SMP-over-I2P | end-to-end (two sims + relay) | `tools/e2e-smp-i2p.sh` |
| Ratchet | known-answer tests | `swift test --filter RatchetTests` |

The architecture's stability contract (§10) is enforced by API-boundary tests so transports can be
improved without touching the controller.

---

## 7. CI (planned)

- GitHub Actions: `swift build`/`swift test` for all packages; `cabal build`/`cabal test` for the
  reference SMP relay; `make` for i2pd; a nightly mesh simulator test.
- Release builds are **reproducible** with a pinned `versions.json` (as Telegram-iOS does) so a
  build can be verified against the source hash manifest (bitchat's verified-build approach).

---

## 8. Troubleshooting

- **`swift build` can't find Rust toolchain** → install via `rustup`, add the iOS target
  (`rustup target add aarch64-apple-ios`).
- **i2pd won't build** → ensure CMake ≥3.24 and disable AES-NI/AVX for simulator
  (`make USE_AESNI=no USE_AVX=no`).
- **Mesh tests pass in sim but fail on device** → expected; BLE mesh is device-only. Use physical
  devices and grant Bluetooth permissions.
- **SMP relay won't init** → open `openssl version`; macOS ships LibreSSL, install OpenSSL
  (`brew install openssl`) as documented in the simplexmq README.