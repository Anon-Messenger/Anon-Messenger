# Anon — Hybrid Anonymous Messenger

Anon combines the best properties of four projects:

| Source | What Anon takes |
| --- | --- |
| **Telegram** | Polished, modern UI/UX design language |
| **SimpleX Chat / SimpleXMQ** | Zero user identifiers + strong metadata protection, SMP queues, double ratchet + PQ key agreement |
| **Bitchat** | Offline Bluetooth LE mesh, multi-transport message router, embedded anonymous network router |
| **I2P (i2pd)** | Anonymous transport for *all* internet traffic (SMP, Nostr fallback, file transfer) |

The result is a messenger that **feels like Telegram**, works **completely offline via BLE mesh**,
requires **zero accounts / phone numbers / usernames**, and routes **all internet traffic through I2P
by default** (with optional Tor fallback for usability).

> **Status:** Architecture phase **plus the M0 foundation**. The technical
> architecture, codebase analysis, milestones, setup, and roadmap are in `docs/`.
> The upstream forks are wired in as git submodules, and a compiling M0 Swift
> skeleton (identity/envelope types, the frozen `AnonTransport` /
> `AnonymousRouter` interfaces, and a tested multi-transport `MessageRouter`) is
> in `Packages/Anon/`.

## Document map

- [`docs/00-analysis-of-existing-codebases.md`](docs/00-analysis-of-existing-codebases.md) — what each upstream repo actually contains and where the integration seams are.
- [`docs/01-technical-architecture.md`](docs/01-technical-architecture.md) — the layering, identity model, transports, and the multi-transport message router.
- [`docs/02-implementation-milestones.md`](docs/02-implementation-milestones.md) — the first four milestones (M0–M3) with concrete, verifiable outcomes.
- [`docs/03-build-and-development-setup.md`](docs/03-build-and-development-setup.md) — toolchain, repository layout, and step-by-step build instructions.
- [`docs/04-post-mvp-roadmap.md`](docs/04-post-mvp-roadmap.md) — post-MVP features (calls, better groups, multi-device, etc.).

## Forks (git submodules)

The org forks and the I2P router are pinned under `submodules/`:

```
submodules/bitchat        https://github.com/Anon-Messenger/bitchat.git      (BLE mesh + Nostr + Arti/Tor)
submodules/simplexmq      https://github.com/Anon-Messenger/simplexmq.git    (SMP protocol/relay + crypto)
submodules/simplex-chat   https://github.com/Anon-Messenger/simplex-chat.git (Haskell core + KMP UI)
submodules/Telegram-iOS   https://github.com/Anon-Messenger/Telegram-iOS.git (UI design reference)
submodules/i2pd           https://github.com/PurpleI2P/i2pd.git              (embedded I2P router, BSD-3)
```

## Building the M0 foundation

The M0 packages are Foundation-only, so they build under Command Line Tools
(no full Xcode.app required on this machine):

```sh
./Tools/build-smoke.sh      # emits 4 static libs + a smoke-test binary
/tmp/anon-router-smoke      # runs the router behavior checks (14 PASS lines)
```

With a full Xcode installation, the same packages build the standard way:

```sh
cd Packages/Anon && swift build && swift test
```

## Platform strategy (summary)

**Start on iOS, native Swift.** Rationale and the full trade-off analysis are in the
architecture document. In short:

- Bitchat (Swift, Unlicense) already ships the hardest pieces — the BLE mesh, the
  `Transport` / `MessageRouter` abstraction, courier store-and-forward, and an embedded
  Tor router — so the offline path is proven, not speculative.
- Telegram-iOS is the same language, giving us a direct visual reference.
- Unlicense (bitchat) + BSD-3 (i2pd) mix cleanly; SimpleX stays a protocol + philosophy
  source (AGPL) rather than a linked code dependency on mobile.

## License

Anon is licensed under **AGPL-3.0-or-later**. Bitchat-derived code is compatible
(public domain / Unlicense). i2pd is BSD-3-Clause. No Telegram-iOS code is copied —
only its design language, to avoid GPL/TDLib/cloud-identity entanglement.