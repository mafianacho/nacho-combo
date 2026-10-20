// swift-tools-version:5.5
import PackageDescription

var products: [Product] = [.library(name: "NachoComboCore", targets: ["NachoComboCore"])]
var targets: [Target] = [
    // Foundation-only logic (settings, module lifecycle, math). Testable on any OS.
    .target(name: "NachoComboCore"),
    .testTarget(name: "NachoComboCoreTests", dependencies: ["NachoComboCore"]),
]

#if os(macOS)
// AppKit / Carbon / Accessibility layer. macOS only; skipped on Linux so the core can be tested there.
products.append(.executable(name: "NachoCombo", targets: ["NachoCombo"]))
targets.append(.executableTarget(name: "NachoCombo", dependencies: ["NachoComboCore"]))
#endif

let package = Package(
    name: "NachoCombo",
    platforms: [.macOS(.v12)],
    products: products,
    targets: targets
)
