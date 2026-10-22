import AppKit
import NachoComboCore

/// Level 1: the feature list.
final class ToolListView: NSView {
    private weak var host: PanelHost?
    private var rows: [ModuleID: ToolRowView] = [:]
    var onSelect: ((ModuleID) -> Void)?
    var firstRow: ToolRowView? { ModuleID.allCases.first.flatMap { rows[$0] } }

    init(host: PanelHost) {
        self.host = host
        super.init(frame: .zero)
        let inner = UI.panelWidth - 24

        let title = UI.label("Nacho Combo", size: 14, weight: .semibold)
        let caption = UI.label("도구", size: 11, color: .secondaryLabelColor)
        let header = UI.hstack([title, UI.spacer(), caption], spacing: 6)
        header.widthAnchor.constraint(equalToConstant: inner).isActive = true

        var views: [NSView] = [header, UI.separator(width: inner)]
        for id in ModuleID.allCases {
            let row = ToolRowView(module: id)
            row.setAccessibilityIdentifier("panel-row-\(id.rawValue)")
            row.onActivate = { [weak self] id in self?.onSelect?(id) }
            row.widthAnchor.constraint(equalToConstant: inner).isActive = true
            rows[id] = row
            views.append(row)
        }
        views.append(UI.separator(width: inner))

        let settings = UI.linkButton("설정…", color: .labelColor, target: self, action: #selector(settingsClicked))
        settings.setAccessibilityIdentifier("panel-settings")
        let quit = UI.linkButton("종료", color: .labelColor, target: self, action: #selector(quitClicked))
        quit.setAccessibilityIdentifier("panel-quit")
        let footer = UI.hstack([settings, UI.spacer(), quit], spacing: 6)
        footer.widthAnchor.constraint(equalToConstant: inner).isActive = true
        views.append(footer)

        let stack = UI.vstack(views, spacing: 4)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            widthAnchor.constraint(equalToConstant: UI.panelWidth),
        ])
        update()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func update() {
        guard let host = host else { return }
        let manager = host.panelManager
        for id in ModuleID.allCases {
            rows[id]?.configure(status: manager.status(of: id), pinned: manager.settings.isPinned(id),
                                shortcut: manager.settings.shortcut(for: id))
        }
    }

    @objc private func settingsClicked() { host?.panelOpenSettings() }
    @objc private func quitClicked() { host?.panelQuit() }
}

/// Level 2: the controls of one tool. Never starts a tool or asks for a permission by itself:
/// the user presses the switch (or the permission buttons) explicitly.
final class ToolDetailView: NSView {
    private weak var host: PanelHost?
    private let module: ModuleID
    var onBack: (() -> Void)?

    private let dot = StatusDotView()
    private let stateLabel = UI.label("", size: 12, weight: .medium, color: .secondaryLabelColor)
    private let enableSwitch = NSSwitch()
    private let messageLabel: NSTextField
    private let permissionRow = NSStackView()
    private let pinStatus = UI.label("", size: 12, weight: .medium)
    private let pinButton: NSButton
    private let shortcutLabel = UI.label("", size: 11, color: .secondaryLabelColor)
    private var controls: [NSControl] = []
    private let inner = UI.panelWidth - 28

    // tool specific
    private let collapseButton = NSButton(title: "숨김 아이콘 접기", target: nil, action: nil)
    private let cpuValue = UI.label("–", size: 12, color: .labelColor)
    private let memValue = UI.label("–", size: 12, color: .labelColor)
    private let rxValue = UI.label("–", size: 12, color: .labelColor)
    private let txValue = UI.label("–", size: 12, color: .labelColor)
    private let snapSegments = NSSegmentedControl(labels: SnapAction.allCases.map { $0.displayName },
                                                  trackingMode: .selectOne, target: nil, action: nil)
    private let snapPreview = SnapPreviewView()
    private let snapApply = NSButton(title: "적용", target: nil, action: nil)
    private let shelfButton = NSButton(title: "선반 열기", target: nil, action: nil)
    private let shelfCount = UI.label("", size: 11, color: .secondaryLabelColor)
    private let captureButton = NSButton(title: "영역 캡처 시작", target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0.5, minValue: FocusDimLogic.minimumIntensity,
                                     maxValue: FocusDimLogic.maximumIntensity, target: nil, action: nil)
    private let dimValue = UI.label("", size: 12, color: .labelColor)
    private var snapSelection: SnapAction = .left

    init(module: ModuleID, host: PanelHost) {
        self.module = module
        self.host = host
        self.messageLabel = UI.wrapLabel("", width: UI.panelWidth - 28, size: 11, color: .labelColor)
        self.pinButton = NSButton(title: "", target: nil, action: nil)
        super.init(frame: .zero)

        let back = UI.linkButton("‹ 모든 도구", target: self, action: #selector(backClicked))
        back.setAccessibilityIdentifier("panel-back")
        back.setAccessibilityLabel("모든 도구로 돌아가기")
        let esc = UI.label("Esc", size: 11, color: .tertiaryLabelColor)
        esc.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        esc.setAccessibilityElement(false)
        let top = UI.hstack([back, UI.spacer(), esc], spacing: 6)

        let symbol = UI.symbolView(module.symbolName, size: 16)
        let name = UI.label(module.displayName, size: 15, weight: .semibold)
        name.setAccessibilityIdentifier("panel-title")
        let titleRow = UI.hstack([symbol, name, UI.spacer(), dot, stateLabel], spacing: 8)
        stateLabel.setAccessibilityIdentifier("panel-state")

        let enableLabel = UI.label("사용", size: 12)
        enableSwitch.target = self
        enableSwitch.action = #selector(enableToggled)
        enableSwitch.setAccessibilityLabel("\(module.displayName) 사용")
        enableSwitch.setAccessibilityIdentifier("panel-enable")
        let enableRow = UI.hstack([enableLabel, UI.spacer(), enableSwitch], spacing: 8)

        messageLabel.isHidden = true
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 8
        permissionRow.isHidden = true
        permissionRow.translatesAutoresizingMaskIntoConstraints = false
        let openPane = NSButton(title: module == .captureFloat ? "화면 기록 설정 열기" : "손쉬운 사용 설정 열기",
                                target: self, action: #selector(openPaneClicked))
        openPane.setAccessibilityIdentifier("panel-open-permission")
        let recheck = NSButton(title: "권한 다시 확인", target: self, action: #selector(recheckClicked))
        recheck.setAccessibilityIdentifier("panel-recheck")
        permissionRow.addArrangedSubview(openPane)
        permissionRow.addArrangedSubview(recheck)

        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        pinButton.setAccessibilityIdentifier("panel-pin")
        let pinRow = OutlinedRow(views: [pinStatus, UI.spacer(), pinButton])
        pinRow.orientation = .horizontal
        pinRow.alignment = .centerY
        pinRow.spacing = 8
        pinRow.translatesAutoresizingMaskIntoConstraints = false
        pinRow.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        // Fixed frame: the label keeps the same size for both states, so nothing has to be erased outside it.
        pinStatus.translatesAutoresizingMaskIntoConstraints = false
        pinStatus.widthAnchor.constraint(equalToConstant: 150).isActive = true
        pinStatus.drawsBackground = true
        pinStatus.backgroundColor = .controlBackgroundColor

        let desc = UI.wrapLabel(module.toolSummary, width: inner, size: 12)

        var views: [NSView] = [top, titleRow, enableRow, messageLabel, permissionRow, pinRow, desc]
        views.append(contentsOf: toolSpecificViews())
        shortcutLabel.setAccessibilityIdentifier("panel-shortcut")
        views.append(shortcutLabel)
        views.append(UI.separator(width: inner))
        let settingsLink = UI.linkButton("\(module.displayName) 설정…", target: self, action: #selector(settingsClicked))
        settingsLink.setAccessibilityIdentifier("panel-tool-settings")
        let arrow = UI.label("↗", size: 12, color: .secondaryLabelColor)
        arrow.setAccessibilityElement(false)
        views.append(UI.hstack([settingsLink, UI.spacer(), arrow], spacing: 6))

        let stack = UI.vstack(views, spacing: 10)
        for v in views where v is NSStackView { v.widthAnchor.constraint(equalToConstant: inner).isActive = true }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            widthAnchor.constraint(equalToConstant: UI.panelWidth),
        ])
        update()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: tool specific controls

    private func toolSpecificViews() -> [NSView] {
        switch module {
        case .menuBar:
            collapseButton.target = self
            collapseButton.action = #selector(collapseClicked)
            collapseButton.setAccessibilityIdentifier("panel-collapse")
            controls.append(collapseButton)
            let note = UI.wrapLabel("숨길 아이콘은 ⌘ 키를 누른 채 구분선(┊) 왼쪽으로 끌어 놓습니다.", width: inner)
            return [collapseButton, note]
        case .systemMonitor:
            func line(_ title: String, _ value: NSTextField) -> NSView {
                value.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                value.alignment = .right      // fixed-size, right-aligned: the frame never changes while values update
                value.translatesAutoresizingMaskIntoConstraints = false
                value.widthAnchor.constraint(equalToConstant: 170).isActive = true
                return UI.hstack([UI.label(title, size: 12, color: .secondaryLabelColor), UI.spacer(), value], spacing: 6)
            }
            cpuValue.setAccessibilityIdentifier("panel-cpu")
            memValue.setAccessibilityIdentifier("panel-mem")
            rxValue.setAccessibilityIdentifier("panel-rx")
            txValue.setAccessibilityIdentifier("panel-tx")
            return [line("CPU", cpuValue), line("메모리", memValue), line("네트워크 ↓", rxValue), line("네트워크 ↑", txValue)]
        case .windowSnap:
            snapSegments.target = self
            snapSegments.action = #selector(snapSelected)
            snapSegments.selectedSegment = 0
            snapSegments.setAccessibilityIdentifier("panel-snap-choice")
            snapApply.target = self
            snapApply.action = #selector(snapApplyClicked)
            snapApply.bezelStyle = .rounded
            snapApply.keyEquivalent = ""
            snapApply.setAccessibilityIdentifier("panel-snap-apply")
            snapPreview.action = .left
            snapPreview.setAccessibilityElement(true)
            snapPreview.setAccessibilityLabel("배치 미리보기: 왼쪽 절반")
            controls.append(contentsOf: [snapSegments, snapApply])
            let row = UI.hstack([snapPreview, UI.vstack([snapSegments, snapApply], spacing: 8)], spacing: 12, alignment: .top)
            let note = UI.wrapLabel("직전에 쓰던 앱의 창이 대상입니다. 손쉬운 사용 권한이 필요합니다.", width: inner)
            return [row, note]
        case .fileShelf:
            shelfButton.target = self
            shelfButton.action = #selector(shelfClicked)
            shelfButton.setAccessibilityIdentifier("panel-shelf-toggle")
            controls.append(shelfButton)
            shelfCount.setAccessibilityIdentifier("panel-shelf-count")
            return [UI.hstack([shelfButton, shelfCount], spacing: 10)]
        case .captureFloat:
            captureButton.target = self
            captureButton.action = #selector(captureClicked)
            captureButton.setAccessibilityIdentifier("panel-capture-start")
            controls.append(captureButton)
            let note = UI.wrapLabel("패널이 닫힌 뒤 영역을 고릅니다. 켤 때 화면 기록 권한 동의가 필요합니다.", width: inner)
            return [captureButton, note]
        case .focusDim:
            dimSlider.target = self
            dimSlider.action = #selector(dimChanged(_:))
            dimSlider.isContinuous = true
            dimSlider.setAccessibilityIdentifier("panel-dim-slider")
            dimSlider.setAccessibilityLabel("디밍 강도")
            dimValue.setAccessibilityIdentifier("panel-dim-value")
            let row = UI.hstack([UI.label("강도", size: 12, color: .secondaryLabelColor), dimSlider, dimValue], spacing: 8)
            dimSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
            return [row]
        }
    }

    // MARK: state

    func update() {
        guard let host = host else { return }
        let manager = host.panelManager
        let status = manager.status(of: module)
        let enabled = manager.settings.isEnabled(module)
        dot.kind = status.dot
        dot.setAccessibilityLabel(status.accessibilityText)
        dot.toolTip = status.accessibilityText
        stateLabel.setLive(status.stateText)
        enableSwitch.state = enabled ? .on : .off

        if let detail = status.detail {
            messageLabel.setLive("⚠︎ " + detail + (status.dot == .onNeedsSetup ? "\n허용하기 전까지 이 도구는 동작하지 않습니다." : ""))
            messageLabel.isHidden = false
        } else {
            messageLabel.isHidden = true
        }
        let showsPermission = status.dot == .onNeedsSetup && (module == .windowSnap || module == .captureFloat)
        permissionRow.isHidden = !showsPermission

        let pinned = manager.settings.isPinned(module)
        pinStatus.setLive(pinned ? "상단바 고정됨" : "상단바에 고정되지 않음")
        pinStatus.textColor = pinned ? NSColor.systemOrange : NSColor.secondaryLabelColor
        pinStatus.invalidateAncestors()
        let pinTitle = pinned ? "고정 해제" : "상단바에 고정"
        pinButton.attributedTitle = NSAttributedString(string: pinTitle, attributes: [
            .foregroundColor: NSColor.controlAccentColor, .font: NSFont.systemFont(ofSize: 12)])
        pinButton.setAccessibilityLabel("\(module.displayName) \(pinTitle)")
        pinButton.invalidateAncestors()

        if let shortcut = manager.settings.shortcut(for: module) {
            shortcutLabel.setLive("이 화면 열기 단축키: \(shortcut.label)")
        } else {
            shortcutLabel.setLive("이 화면 열기 단축키: 미설정 (설정 창에서 지정)")
        }

        let running = status.dot == .on
        for c in controls { c.isEnabled = running }
        switch module {
        case .menuBar:
            let info = host.panelCollapse
            collapseButton.isEnabled = running && info.running
            collapseButton.title = info.collapsed ? "숨김 아이콘 펼치기" : "숨김 아이콘 접기"
        case .systemMonitor:
            let r = host.panelReading
            if running {
                cpuValue.setLive(r.cpuBusy.map { String(format: "%.0f%%", $0) } ?? "–")
                memValue.setLive(r.memPercent.map {
                    String(format: "%.0f%%", $0) + " (\(SystemMath.formatBytes(r.memUsed)) / \(SystemMath.formatBytes(r.memTotal)))"
                } ?? "–")
                rxValue.setLive(r.rx.map { SystemMath.formatRateCompact($0) + "/s" } ?? "–")
                txValue.setLive(r.tx.map { SystemMath.formatRateCompact($0) + "/s" } ?? "–")
            } else {
                for v in [cpuValue, memValue, rxValue, txValue] { v.setLive("–") }
            }
        case .fileShelf:
            let info = host.panelShelf
            shelfButton.title = info.visible ? "선반 닫기" : "선반 열기"
            shelfCount.setLive(running ? "\(info.count)개 항목" : "")
        case .focusDim:
            if NSApp.currentEvent?.type != .leftMouseDragged { dimSlider.doubleValue = manager.settings.dimIntensity }
            dimValue.setLive("\(Int((manager.settings.dimIntensity * 100).rounded()))%")
        default: break
        }
        if !running && module != .focusDim {
            // Say why the controls are dimmed instead of leaving a silent, disabled panel.
            toolTip = enabled ? "상태를 확인하세요" : "켜면 사용할 수 있습니다"
        } else {
            toolTip = nil
        }
    }

    // MARK: actions

    @objc private func backClicked() { onBack?() }
    @objc private func enableToggled() { host?.panelSetEnabled(module, enableSwitch.state == .on) }
    @objc private func pinClicked() {
        guard let host = host else { return }
        host.panelSetPinned(module, !host.panelManager.settings.isPinned(module))
    }
    @objc private func settingsClicked() { host?.panelOpenSettings() }
    @objc private func openPaneClicked() { host?.panelOpenPermissionPane(module) }
    @objc private func recheckClicked() { host?.panelRecheck(module) }
    @objc private func collapseClicked() { host?.panelToggleCollapse() }
    @objc private func shelfClicked() { host?.panelToggleShelf() }
    @objc private func captureClicked() { host?.panelStartCapture() }
    @objc private func dimChanged(_ sender: NSSlider) { host?.panelSetDim(sender.doubleValue) }
    @objc private func snapSelected() {
        let i = max(0, snapSegments.selectedSegment)
        snapSelection = SnapAction.allCases[i]
        snapPreview.action = snapSelection
    }
    @objc private func snapApplyClicked() { host?.panelApplySnap(snapSelection) }
}
