import AppKit
import NachoComboCore

/// One window for every gadget: an independent switch, a description, the *actual* state
/// (꺼짐 / 동작 중 / 권한 필요 / 오류) and, when needed, the permission guidance for that gadget.
/// A switch being on never implies "running": the state label always comes from the module's start result.
final class SettingsWindowController: NSObject {
    private let manager: ModuleManager
    private let organizer: MenuBarOrganizerModule
    private let window: NSWindow

    private var checkboxes: [ModuleID: NSButton] = [:]
    private var statusLabels: [ModuleID: NSTextField] = [:]
    private var messageLabels: [ModuleID: NSTextField] = [:]
    private var permissionRows: [ModuleID: NSStackView] = [:]
    private var dots: [ModuleID: StatusDotView] = [:]
    private var pinChecks: [ModuleID: NSButton] = [:]
    private var recorders: [ModuleID: ShortcutRecorderButton] = [:]
    private var shortcutMessages: [ModuleID: NSTextField] = [:]

    private let collapseButton = NSButton(title: "숨김 아이콘 접기", target: nil, action: nil)
    private let shelfButton = NSButton(title: "선반 열기", target: nil, action: nil)
    private let captureButton = NSButton(title: "영역 캡처 시작", target: nil, action: nil)
    private let releaseDimButton = NSButton(title: "디밍 즉시 해제", target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0.5, minValue: FocusDimLogic.minimumIntensity,
                                     maxValue: FocusDimLogic.maximumIntensity, target: nil, action: nil)
    private let dimLabel = NSTextField(labelWithString: "")

    var openAccessibilitySettings: (() -> Void)?
    var recheckPermission: (() -> Void)?
    var openScreenRecordingSettings: (() -> Void)?
    var recheckScreenRecording: (() -> Void)?
    var toggleShelf: (() -> Void)?
    var startCapture: (() -> Void)?
    var releaseDim: (() -> Void)?
    var dimIntensityChanged: ((Double) -> Void)?
    var shelfVisible: (() -> Bool)?
    var quitApp: (() -> Void)?
    var pinChanged: ((ModuleID, Bool) -> Void)?
    /// Returns an error message when the shortcut was refused (policy or OS), nil when it was saved/cleared.
    var shortcutRecorded: ((ModuleID, ToolShortcut?) -> String?)?
    var recordingChanged: ((Bool) -> Void)?

    private static let hints: [ModuleID: String] = [
        .menuBar: "구분선(┊) 왼쪽의 아이콘을 접습니다. 숨길 아이콘은 ⌘ 키를 누른 채 구분선 왼쪽으로 끌어 놓습니다. 권한 불필요.",
        .systemMonitor: "메뉴 막대에 CPU·메모리·네트워크 속도를 표시합니다(2초 간격). 권한 불필요.",
        .windowSnap: "⌃⌥← 왼쪽 절반 · ⌃⌥→ 오른쪽 절반 · ⌃⌥↩ 최대화. 켜면 손쉬운 사용 권한 동의가 필요합니다.",
        .fileShelf: "파일·이미지·텍스트를 선반에 끌어다 놓고 다른 앱으로 다시 끌어냅니다(복사만, 원본 이동·삭제 없음). \(ShelfModule.hotKeyLabel)로 열기/닫기. 권한 불필요.",
        .captureFloat: "\(CaptureFloatModule.hotKeyLabel)로 영역을 선택해 캡처하고 다른 창 위에 고정합니다. 이동·크기 조절·복사·저장·고정 해제·닫기 지원. 켜면 화면 기록 권한 동의가 필요합니다.",
        .focusDim: "활성 창만 밝게 두고 배경 창을 어둡게 합니다(클릭은 그대로 통과). \(FocusDimModule.hotKeyLabel)로 즉시 해제. 권한 불필요.",
    ]

    init(manager: ModuleManager, organizer: MenuBarOrganizerModule) {
        self.manager = manager
        self.organizer = organizer
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Nacho Combo"
        window.isReleasedWhenClosed = false   // closing the window never stops a running gadget
        build()
        refresh()
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        refresh()
        if !window.isVisible {
            // Fit small screens (e.g. 1280×800 with menu bar and Dock): the card list scrolls when it does not fit.
            let available = (NSScreen.main?.visibleFrame.height ?? 800) - 44
            window.setContentSize(NSSize(width: 540, height: min(660, max(420, available))))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: layout

    private func build() {
        let content = NSView()
        window.contentView = content

        let title = NSTextField(labelWithString: "Nacho Combo")
        title.font = NSFont.boldSystemFont(ofSize: 18)
        let subtitle = NSTextField(wrappingLabelWithString:
            "각 도구를 따로 켜고 끕니다. 끄면 그 도구의 감시·단축키·오버레이가 모두 중지됩니다. 이 창을 닫아도 켜 둔 도구는 계속 동작합니다.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.preferredMaxLayoutWidth = 480
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        list.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        list.translatesAutoresizingMaskIntoConstraints = false
        for id in ModuleID.allCases { list.addArrangedSubview(makeCard(for: id)) }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let quit = NSButton(title: "Nacho Combo 종료", target: self, action: #selector(quitClicked))
        quit.setAccessibilityIdentifier("quit-app")
        let footnote = NSTextField(wrappingLabelWithString:
            "종료하면 모든 가젯이 정리됩니다. 설정은 자동 저장되어 다음 실행 때 복원됩니다. 메뉴 막대의 NC ▸ 설정…에서 이 창을 다시 열 수 있습니다.")
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.preferredMaxLayoutWidth = 330
        let footer = NSStackView(views: [footnote, quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(header)
        content.addSubview(scroll)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }

    private func makeCard(for id: ModuleID) -> NSView {
        let check = NSButton(checkboxWithTitle: id.displayName, target: self, action: #selector(toggled(_:)))
        check.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        check.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        check.setAccessibilityIdentifier("toggle-\(id.rawValue)")
        checkboxes[id] = check

        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        status.alignment = .right
        status.setAccessibilityIdentifier("status-\(id.rawValue)")
        statusLabels[id] = status

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let dot = StatusDotView()
        dots[id] = dot
        let top = NSStackView(views: [dot, check, spacer, status])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false
        top.widthAnchor.constraint(equalToConstant: 480).isActive = true

        let hint = NSTextField(wrappingLabelWithString: SettingsWindowController.hints[id] ?? "")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.preferredMaxLayoutWidth = 470

        let message = NSTextField(wrappingLabelWithString: "")
        message.font = NSFont.systemFont(ofSize: 11)
        message.textColor = .systemRed
        message.preferredMaxLayoutWidth = 470
        message.isHidden = true
        messageLabels[id] = message

        let card = NSStackView(views: [top, hint, message])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 3

        // Menu bar pin and tool-open shortcut: both are separate from ON/OFF.
        let pin = NSButton(checkboxWithTitle: "메뉴 막대에 고정 (아이콘을 누르면 이 도구 화면으로 바로 이동)", target: self,
                           action: #selector(pinToggled(_:)))
        pin.font = NSFont.systemFont(ofSize: 11)
        pin.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        pin.setAccessibilityIdentifier("pin-\(id.rawValue)")
        pinChecks[id] = pin
        let recorder = ShortcutRecorderButton()
        recorder.controlSize = .small
        recorder.font = NSFont.systemFont(ofSize: 11)
        recorder.setAccessibilityIdentifier("shortcut-\(id.rawValue)")
        recorder.setAccessibilityLabel("\(id.displayName) 화면 열기 단축키")
        recorder.onRecordingChange = { [weak self] on in self?.recordingChanged?(on) }
        recorder.onRecord = { [weak self] shortcut in self?.record(id, shortcut) }
        recorders[id] = recorder
        let clear = NSButton(title: "해제", target: self, action: #selector(clearShortcutClicked(_:)))
        clear.controlSize = .small
        clear.font = NSFont.systemFont(ofSize: 11)
        clear.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        clear.setAccessibilityIdentifier("shortcut-clear-\(id.rawValue)")
        let shortcutTitle = NSTextField(labelWithString: "화면 열기 단축키")
        shortcutTitle.font = NSFont.systemFont(ofSize: 11)
        shortcutTitle.textColor = .secondaryLabelColor
        let shortcutMessage = NSTextField(wrappingLabelWithString: "")
        shortcutMessage.font = NSFont.systemFont(ofSize: 11)
        shortcutMessage.textColor = .systemRed
        shortcutMessage.preferredMaxLayoutWidth = 470
        shortcutMessage.isHidden = true
        shortcutMessage.setAccessibilityIdentifier("shortcut-message-\(id.rawValue)")
        shortcutMessages[id] = shortcutMessage
        card.addArrangedSubview(pin)
        card.addArrangedSubview(actionRow([shortcutTitle, recorder, clear]))
        card.addArrangedSubview(shortcutMessage)

        // Permission guidance lives with the gadget that needs it.
        switch id {
        case .windowSnap:
            let row = permissionButtons(open: #selector(openAccessibilityClicked), title: "손쉬운 사용 설정 열기",
                                        recheck: #selector(recheckAccessibilityClicked))
            permissionRows[id] = row
            card.addArrangedSubview(row)
        case .captureFloat:
            let row = permissionButtons(open: #selector(openScreenClicked), title: "화면 기록 설정 열기",
                                        recheck: #selector(recheckScreenClicked))
            permissionRows[id] = row
            card.addArrangedSubview(row)
        default: break
        }

        switch id {
        case .menuBar:
            collapseButton.target = self
            collapseButton.action = #selector(collapseClicked)
            card.addArrangedSubview(actionRow([collapseButton]))
        case .fileShelf:
            shelfButton.target = self
            shelfButton.action = #selector(shelfClicked)
            card.addArrangedSubview(actionRow([shelfButton]))
        case .captureFloat:
            captureButton.target = self
            captureButton.action = #selector(captureClicked)
            card.addArrangedSubview(actionRow([captureButton]))
        case .focusDim:
            dimSlider.target = self
            dimSlider.action = #selector(dimChanged(_:))
            dimSlider.isContinuous = true
            dimSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
            dimSlider.setAccessibilityIdentifier("dim-intensity")
            releaseDimButton.target = self
            releaseDimButton.action = #selector(releaseDimClicked)
            card.addArrangedSubview(actionRow([dimLabel, dimSlider, releaseDimButton]))
        default: break
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSStackView(views: [card, separator])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 6
        separator.widthAnchor.constraint(equalToConstant: 480).isActive = true
        return wrapper
    }

    private func permissionButtons(open: Selector, title: String, recheck: Selector) -> NSStackView {
        let row = NSStackView(views: [
            NSButton(title: title, target: self, action: open),
            NSButton(title: "권한 다시 확인", target: self, action: recheck),
        ])
        row.orientation = .horizontal
        row.spacing = 8
        row.isHidden = true
        return row
    }

    private func actionRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    // MARK: state

    func refresh() {
        for id in ModuleID.allCases {
            let enabled = manager.settings.isEnabled(id)
            let state = manager.states[id] ?? .off
            checkboxes[id]?.state = enabled ? .on : .off

            var text = state.label
            var color = NSColor.secondaryLabelColor
            var message = ""
            switch state {
            case .running:
                color = .systemGreen
            case .needsPermission(let m):
                color = .systemOrange
                message = "⚠︎ " + m + "\n허용하기 전까지 이 가젯은 동작하지 않습니다."
            case .failed(let m):
                color = .systemRed
                message = "⚠︎ " + m
            case .off:
                break
            }
            // A switch that is on while the module is not running must never read as "동작 중".
            if enabled, case .off = state { text = "시작 대기" }
            dots[id]?.kind = manager.status(of: id).dot
            dots[id]?.setAccessibilityLabel("\(id.displayName) 상태: \(manager.status(of: id).accessibilityText)")
            pinChecks[id]?.state = manager.settings.isPinned(id) ? .on : .off
            if recorders[id]?.isRecording != true { recorders[id]?.shortcut = manager.settings.shortcut(for: id) }
            statusLabels[id]?.stringValue = text
            statusLabels[id]?.textColor = color
            messageLabels[id]?.stringValue = message
            messageLabels[id]?.isHidden = message.isEmpty
            if let row = permissionRows[id] {
                if case .needsPermission = state { row.isHidden = false } else { row.isHidden = true }
            }
        }
        let running: (ModuleID) -> Bool = { self.manager.states[$0] == .running }
        collapseButton.isEnabled = organizer.isRunning
        collapseButton.title = organizer.collapsed ? "숨김 아이콘 펼치기" : "숨김 아이콘 접기"
        shelfButton.isEnabled = running(.fileShelf)
        shelfButton.title = (shelfVisible?() ?? false) ? "선반 닫기" : "선반 열기"
        captureButton.isEnabled = running(.captureFloat)
        releaseDimButton.isEnabled = running(.focusDim)
        dimSlider.doubleValue = manager.settings.dimIntensity
        dimLabel.stringValue = "강도 \(Int((manager.settings.dimIntensity * 100).rounded()))%"
    }

    // MARK: actions

    @objc private func toggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = ModuleID(rawValue: raw) else { return }
        manager.setEnabled(id, sender.state == .on)
    }
    @objc private func pinToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = ModuleID(rawValue: raw) else { return }
        pinChanged?(id, sender.state == .on)
    }
    @objc private func clearShortcutClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = ModuleID(rawValue: raw) else { return }
        _ = shortcutRecorded?(id, nil)
        shortcutMessages[id]?.isHidden = true
    }
    private func record(_ id: ModuleID, _ shortcut: ToolShortcut) {
        let issue = shortcutRecorded?(id, shortcut)
        shortcutMessages[id]?.stringValue = issue.map { "⚠︎ \(shortcut.label): \($0)" } ?? ""
        shortcutMessages[id]?.isHidden = issue == nil
    }
    @objc private func collapseClicked() { organizer.setCollapsed(!organizer.collapsed) }
    @objc private func shelfClicked() { toggleShelf?() }
    @objc private func captureClicked() { startCapture?() }
    @objc private func releaseDimClicked() { releaseDim?() }
    @objc private func dimChanged(_ sender: NSSlider) { dimIntensityChanged?(sender.doubleValue) }
    @objc private func openAccessibilityClicked() { openAccessibilitySettings?() }
    @objc private func recheckAccessibilityClicked() { recheckPermission?() }
    @objc private func openScreenClicked() { openScreenRecordingSettings?() }
    @objc private func recheckScreenClicked() { recheckScreenRecording?() }
    @objc private func quitClicked() { quitApp?() }
}
