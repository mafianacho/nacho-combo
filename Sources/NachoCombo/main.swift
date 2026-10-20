import AppKit
import Foundation

let arguments = CommandLine.arguments

// `NachoCombo ctl <command...>` talks to a running instance started with --debug-ctl.
if arguments.count >= 2, arguments[1] == "ctl" {
    let command = arguments.dropFirst(2).joined(separator: " ")
    DistributedNotificationCenter.default().postNotificationName(
        AppDelegate.commandName, object: nil, userInfo: ["cmd": command], deliverImmediately: true)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))
    if let data = try? Data(contentsOf: Diagnostics.url), let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        print("no state file at \(Diagnostics.url.path)")
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate(debugCtl: arguments.contains("--debug-ctl"))
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
