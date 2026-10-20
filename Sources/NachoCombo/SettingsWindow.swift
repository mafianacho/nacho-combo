import AppKit
import NachoComboCore

final class SettingsWindowController: NSObject {
    private let manager: ModuleManager
    private let organizer: MenuBarOrganizerModule
    private let window: NSWindow
    private var checkboxes: [ModuleID: NSButton] = [:]
    private var statusLabels: [ModuleID: NSTextField] = [:]
    private let permissionBox = NSStackView()
    private let permissionLabel = NSTextField(wrappingLabelWithString: "")
    private let collapseButton = NSButton(title: "숨김 아이콘 접기", target: nil, action: nil)
    var openAccessibilitySettings: (() -> Void)?
    var recheckPermission: (() -> Void)?

    init(manager: ModuleManager, organizer: MenuBarOrganizerModule) {
        self.manager = manager
        self.organizer = organizer
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Nacho Combo"
        window.isReleasedWhenClosed = false
        build()
        refresh()
    }

    func show() {
        refresh()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Nacho Combo")
        title.font = NSFont.boldSystemFont(ofSize: 18)
        root.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "기능을 각각 켜고 끌 수 있습니다. 끄면 해당 기능의 감시·이벤트·단축키가 모두 중지됩니다.")
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)

        let hints: [ModuleID: String] = [
            .menuBar: "구분선(┊) 왼쪽의 아이콘을 접습니다. 숨길 아이콘은 ⌘ 키를 누른 채 구분선 왼쪽으로 끌어 놓습니다. 권한 불필요.",
            .systemMonitor: "메뉴 막대에 CPU·메모리·네트워크 속도를 표시합니다(2초 간격). 권한 불필요.",
            .windowSnap: "⌃⌥← 왼쪽 절반 · ⌃⌥→ 오른쪽 절반 · ⌃⌥↩ 최대화. 손쉬운 사용 권한 필요.",
        ]
        for id in ModuleID.allCases {
            let box = NSStackView()
            box.orientation = .vertical
            box.alignment = .leading
            box.spacing = 3
            let check = NSButton(checkboxWithTitle: id.displayName, target: self, action: #selector(toggled(_:)))
            check.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            check.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
            checkboxes[id] = check
            let hint = NSTextField(wrappingLabelWithString: hints[id] ?? "")
            hint.textColor = .secondaryLabelColor
            hint.font = NSFont.systemFont(ofSize: 11)
            hint.preferredMaxLayoutWidth = 470
            let status = NSTextField(wrappingLabelWithString: "")
            status.font = NSFont.systemFont(ofSize: 11)
            status.preferredMaxLayoutWidth = 470
            statusLabels[id] = status
            box.addArrangedSubview(check)
            box.addArrangedSubview(hint)
            box.addArrangedSubview(status)
            if id == .menuBar {
                collapseButton.target = self
                collapseButton.action = #selector(collapseClicked)
                box.addArrangedSubview(collapseButton)
            }
            root.addArrangedSubview(box)
        }

        permissionBox.orientation = .vertical
        permissionBox.alignment = .leading
        permissionBox.spacing = 6
        permissionLabel.textColor = .systemRed
        permissionLabel.preferredMaxLayoutWidth = 470
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubview(NSButton(title: "손쉬운 사용 설정 열기", target: self, action: #selector(openSettings)))
        buttons.addArrangedSubview(NSButton(title: "권한 다시 확인", target: self, action: #selector(recheck)))
        permissionBox.addArrangedSubview(permissionLabel)
        permissionBox.addArrangedSubview(buttons)
        root.addArrangedSubview(permissionBox)

        window.contentView = NSView()
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor),
        ])
    }

    func refresh() {
        for id in ModuleID.allCases {
            let state = manager.states[id] ?? .off
            checkboxes[id]?.state = manager.settings.isEnabled(id) ? .on : .off
            var text = "상태: \(state.label)"
            var color = NSColor.secondaryLabelColor
            switch state {
            case .running: color = .systemGreen
            case .needsPermission, .failed: color = .systemRed
            case .off: break
            }
            if case .failed(let m) = state { text += " — \(m)" }
            statusLabels[id]?.stringValue = text
            statusLabels[id]?.textColor = color
        }
        collapseButton.isEnabled = organizer.isRunning
        collapseButton.title = organizer.collapsed ? "숨김 아이콘 펼치기" : "숨김 아이콘 접기"
        if case .needsPermission(let message) = manager.states[.windowSnap] ?? .off {
            permissionLabel.stringValue = "⚠︎ " + message + "\n허용하기 전까지 창 배치 단축키는 동작하지 않습니다."
            permissionBox.isHidden = false
        } else {
            permissionBox.isHidden = true
        }
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = ModuleID(rawValue: raw) else { return }
        manager.setEnabled(id, sender.state == .on)
    }
    @objc private func collapseClicked() { organizer.setCollapsed(!organizer.collapsed) }
    @objc private func openSettings() { openAccessibilitySettings?() }
    @objc private func recheck() { recheckPermission?() }
}
