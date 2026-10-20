// Test fixture: a stand-in "third-party" menu bar icon used to verify that the Nacho Combo divider hides it.
// Usage: DummyStatusItem [title]   (run several copies with different titles to simulate many icons)
// Build: swiftc tools/DummyStatusItem.swift -o build/DummyStatusItem
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.title = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "◆TEST"
let menu = NSMenu()
menu.addItem(withTitle: "Dummy status item", action: nil, keyEquivalent: "")
item.menu = menu
app.run()
