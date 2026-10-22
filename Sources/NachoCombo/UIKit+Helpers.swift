import AppKit
import NachoComboCore

enum UI {
    static let panelWidth: CGFloat = 320

    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let f = LiveLabel(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    /// Wrapping label with a fixed width so Auto Layout can compute the height before the popover is sized.
    static func wrapLabel(_ text: String, width: CGFloat, size: CGFloat = 11,
                          color: NSColor = .secondaryLabelColor) -> NSTextField {
        let f = LiveLabel(wrappingLabelWithString: text)
        f.font = NSFont.systemFont(ofSize: size)
        f.textColor = color
        f.preferredMaxLayoutWidth = width
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    static func symbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .regular,
                       description: String? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return base.withSymbolConfiguration(config) ?? base
    }

    static func symbolView(_ name: String, size: CGFloat = 14, tint: NSColor = .labelColor) -> NSImageView {
        let v = NSImageView(image: symbol(name, size: size) ?? NSImage())
        v.contentTintColor = tint
        v.imageScaling = .scaleProportionallyDown
        v.setAccessibilityElement(false)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: size + 6).isActive = true
        v.heightAnchor.constraint(equalToConstant: size + 6).isActive = true
        return v
    }

    static func hstack(_ views: [NSView], spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .centerY)
        -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = alignment
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    static func vstack(_ views: [NSView], spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .leading)
        -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = alignment
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    static func separator(width: CGFloat) -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
        return b
    }

    static func linkButton(_ title: String, color: NSColor = .controlAccentColor, target: AnyObject?, action: Selector?)
        -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.isBordered = false
        b.contentTintColor = color
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
        b.setAccessibilityLabel(title)
        return b
    }

    static func modifiersToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= ToolShortcut.command }
        if flags.contains(.shift) { m |= ToolShortcut.shift }
        if flags.contains(.option) { m |= ToolShortcut.option }
        if flags.contains(.control) { m |= ToolShortcut.control }
        return m
    }
}

/// Status circle. Green = switched on, gray = off. A yellow (setup/permission) or red (error) circle sits half behind
/// the green one. It is only a summary: the state is always repeated as text / accessibility value elsewhere.
final class StatusDotView: NSView {
    var kind: StatusDotKind = .off { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 17, height: 12) }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 10
        let y = (bounds.height - d) / 2
        let front = NSRect(x: 0, y: y, width: d, height: d)
        let behind = NSRect(x: 5, y: y, width: d, height: d)
        switch kind {
        case .off:
            NSColor.systemGray.setFill()
            NSBezierPath(ovalIn: front).fill()
        case .on:
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: front).fill()
        case .onNeedsSetup, .onError:
            (kind == .onError ? NSColor.systemRed : NSColor.systemYellow).setFill()
            NSBezierPath(ovalIn: behind).fill()
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: front).fill()
            // a thin ring keeps the overlap readable on any background
            NSColor.windowBackgroundColor.setStroke()
            let ring = NSBezierPath(ovalIn: front.insetBy(dx: -0.5, dy: -0.5))
            ring.lineWidth = 1
            ring.stroke()
        }
    }
}

/// One feature row: status circle, symbol, name, (pin), open-shortcut, arrow. Click or Space/Return opens the tool.
final class ToolRowView: NSControl {
    let module: ModuleID
    var onActivate: ((ModuleID) -> Void)?
    private let dot = StatusDotView()
    private let shortcutLabel = UI.label("", size: 11, color: .tertiaryLabelColor)
    private let pinView = UI.symbolView("pin.fill", size: 10, tint: .systemOrange)
    private var hover = false { didSet { updateBackground() } }
    private var pressed = false { didSet { updateBackground() } }
    private var tracking: NSTrackingArea?

    init(module: ModuleID) {
        self.module = module
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        focusRingType = .exterior
        setAccessibilityRole(.button)

        let symbol = UI.symbolView(module.symbolName, size: 14, tint: .labelColor)
        let name = UI.label(module.displayName, size: 13, weight: .medium)
        let chevron = UI.symbolView("chevron.right", size: 10, tint: .tertiaryLabelColor)
        pinView.isHidden = true
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let row = UI.hstack([dot, symbol, name, UI.spacer(), pinView, shortcutLabel, chevron], spacing: 8)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 34),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(status: ToolStatusPresentation, pinned: Bool, shortcut: ToolShortcut?) {
        dot.kind = status.dot
        pinView.isHidden = !pinned
        shortcutLabel.stringValue = shortcut?.label ?? "미설정"
        shortcutLabel.textColor = shortcut == nil ? .tertiaryLabelColor : .secondaryLabelColor
        let shortcutText = shortcut.map { "열기 단축키 \($0.label)" } ?? "열기 단축키 미설정"
        toolTip = "\(module.displayName) — \(status.stateText)" + (status.detail.map { "\n\($0)" } ?? "")
        setAccessibilityLabel(module.displayName)
        setAccessibilityValue("\(status.accessibilityText)\(pinned ? ", 메뉴 막대에 고정됨" : ""), \(shortcutText)")
        setAccessibilityHelp("도구 조작 화면을 엽니다")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?(module) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76: onActivate?(module)                 // Return, Space, Enter
        case 125: window?.selectNextKeyView(nil)             // Down
        case 126: window?.selectPreviousKeyView(nil)         // Up
        default: super.keyDown(with: event)
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    private func updateBackground() {
        let base = NSColor.labelColor
        layer?.backgroundColor = (pressed ? base.withAlphaComponent(0.16) : hover ? base.withAlphaComponent(0.08) : .clear).cgColor
    }
}

/// Mini screen showing where the chosen window action will put the window.
final class SnapPreviewView: NSView {
    var action: SnapAction = .left { didSet { needsDisplay = true; setAccessibilityLabel("배치 미리보기: \(action.displayName)") } }

    override var intrinsicContentSize: NSSize { NSSize(width: 128, height: 80) }

    override func draw(_ dirtyRect: NSRect) {
        let screen = bounds.insetBy(dx: 1, dy: 1)
        NSColor.quaternaryLabelColor.setFill()
        let outline = NSBezierPath(roundedRect: screen, xRadius: 4, yRadius: 4)
        outline.fill()
        let f = WindowLayout.previewFraction(for: action)
        let inner = screen.insetBy(dx: 3, dy: 3)
        let r = NSRect(x: inner.minX + f.minX * inner.width, y: inner.minY + f.minY * inner.height,
                       width: f.width * inner.width, height: f.height * inner.height).insetBy(dx: 1, dy: 1)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

extension NSView {
    func invalidateAncestors() {
        var view: NSView? = self
        while let current = view {
            current.needsDisplay = true
            view = current.superview
        }
        if let window = window {
            window.contentView?.superview?.setNeedsDisplay(window.contentView?.superview?.bounds ?? .zero)
            window.display()
        }
    }
}

extension NSTextField {
    /// Changing text can shrink the label's frame; the pixels it no longer covers belong to transparent ancestors (row,
    /// vibrancy popover frame) and were not repainted on Monterey, so old and new glyphs showed through each other
    /// (real-OS captures: CPU digits, "상단바 고정됨" -> "상단바에 고정되지 않음"). Invalidate the whole ancestor chain
    /// and flush the window so the stale pixels are repainted.
    func setLive(_ text: String) {
        guard stringValue != text else { return }
        stringValue = text
        invalidateAncestors()
    }
}

/// A horizontal row with a drawn (not layer-backed) rounded outline. A layer-backed row hosting plain text fields kept
/// old glyphs on screen on Monterey when the text changed, so the border is drawn in draw(_:) instead.
final class OutlinedRow: NSStackView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        // Opaque fill: the labels inside draw an identical opaque background, so changed text always repaints cleanly.
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Text drawn inside the popover's vibrancy view is composited with a blend mode, so new glyphs were laid over the old
/// ones instead of replacing them (seen on Monterey whenever a secondary-colour label got longer). Opting out of vibrancy
/// makes the label paint normally and erase what was there.
final class LiveLabel: NSTextField {
    override var allowsVibrancy: Bool { false }
}
