import AnonCore
import SwiftUI

// --- Wire the simulated mesh ------------------------------------------------
//
// This stands in for M1: two remote "devices" behind a shared mesh bus. The
// local profile talks to each remote through the Anon MessageRouter → mesh
// transport path, so messages actually traverse the router end to end.

let local = ChatController(peer: "anon-local")

let nova = ChatController(peer: "anon-remote-1")
nova.autoReply = { _ in "roger that — offline mesh ok 👍" }

let relay = ChatController(peer: "anon-remote-2")
relay.autoReply = { input in
    "relayed over 2 hops: \(input.uppercased())"
}

let bus = MeshBus()
bus.connect(("anon-local", local.transportNode), ("anon-remote-1", nova.transportNode))
bus.connect(("anon-local", local.transportNode), ("anon-remote-2", relay.transportNode))

// Seed a couple of messages so the chat list isn't empty on first launch.
local.seedIncoming(text: "Nova is in range, offline mesh ready.", from: "anon-remote-1")
local.seedIncoming(text: "Relay hop established; reach is ~3 nodes.", from: "anon-remote-2")

// --- Launch the app ---------------------------------------------------------
let app = AnonApp(local: local)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Anon"
window.center()
window.contentView = NSHostingView(rootView: app)
window.makeKeyAndOrderFront(nil)

NSApplication.shared.run()