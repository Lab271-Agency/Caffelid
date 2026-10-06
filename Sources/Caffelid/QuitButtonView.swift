import AppKit

@MainActor
final class QuitButtonView: NSView {
    private let button = QuitButton(frame: NSRect(x: 18, y: 8, width: 270, height: 32))
    var onQuit: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 306, height: 48))
        autoresizingMask = [.width]
        button.autoresizingMask = [.width]
        button.title = Strings.text("quit")
        button.target = self
        button.action = #selector(pressed)
        addSubview(button)
    }

    required init?(coder: NSCoder) { nil }

    func update(enabled: Bool) { button.isEnabled = enabled }

    @objc private func pressed() {
        enclosingMenuItem?.menu?.cancelTracking()
        onQuit?()
    }
}

@MainActor
private final class QuitButton: NSButton {
    override var allowsVibrancy: Bool { false }
    override var focusRingMaskBounds: NSRect { bounds }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.momentaryPushIn)
        isBordered = false
        font = .systemFont(ofSize: 13, weight: .medium)
    }

    required init?(coder: NSCoder) { nil }

    private var buttonShape: NSBezierPath {
        let radius = bounds.height / 2
        return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = buttonShape
        let opacity = isEnabled ? (isHighlighted ? 0.45 : 0.35) : 0.1
        NSColor.systemRed.withAlphaComponent(opacity).setFill()
        shape.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.labelColor.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.menuFont(ofSize: 13),
            .foregroundColor: isEnabled ? NSColor.labelColor : .disabledControlTextColor
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func drawFocusRingMask() {
        buttonShape.fill()
    }
}
