import AppKit

@MainActor
final class MenuToggleView: NSView {
    private let label = MenuTextField(labelWithString: "")
    private let toggle = AccentSwitch()
    private var acceptsChanges = false
    private var presentedState: NSControl.StateValue = .off
    private let title: String?
    private let help: String
    var onChange: (() -> Void)?

    init(title: String? = nil, accessibilityLabel: String, help: String) {
        self.title = title
        self.help = help
        super.init(frame: NSRect(x: 0, y: 0, width: 306, height: 36))
        label.frame = NSRect(x: 18, y: 9, width: 218, height: 18)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.stringValue = title ?? Strings.text("toggle.disabled")
        toggle.setFrameSize(toggle.intrinsicContentSize)
        toggle.setFrameOrigin(NSPoint(x: 288 - toggle.frame.width, y: (36 - toggle.frame.height) / 2))
        toggle.target = self
        toggle.action = #selector(changed)
        toggle.setAccessibilityLabel(accessibilityLabel)
        addSubview(label)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { nil }

    func update(active: Bool, available: Bool, busy: Bool, reason: String?) {
        let text = Strings.text(active ? "toggle.enabled" : "toggle.disabled")
        if label.stringValue != (title ?? text) { label.stringValue = title ?? text }
        presentedState = active ? .on : .off
        toggle.state = presentedState
        toggle.isEnabled = available
        toggle.needsDisplay = true
        acceptsChanges = available && !busy
        let description = busy ? Strings.text("working") : reason
        toolTip = description
        toggle.toolTip = description
        toggle.setAccessibilityValueDescription(text)
        toggle.setAccessibilityHelp(description ?? help)
    }

    @objc private func changed() {
        guard acceptsChanges else {
            toggle.state = presentedState
            toggle.needsDisplay = true
            return
        }
        acceptsChanges = false
        onChange?()
    }
}
