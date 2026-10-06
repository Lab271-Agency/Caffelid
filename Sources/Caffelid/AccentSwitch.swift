import AppKit

// Keep AppKit's button interaction, keyboard handling and accessibility, while
// drawing the track with the system accent even in a menu's non-key window.
@MainActor
final class AccentSwitch: NSButton {
    override var intrinsicContentSize: NSSize { NSSize(width: 54, height: 24) }
    override var allowsVibrancy: Bool { false }
    private var track: NSRect { NSRect(x: 6, y: 1, width: 42, height: 22) }
    override var focusRingMaskBounds: NSRect { track }

    init() {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 54, height: 24)))
        setButtonType(.switch)
        title = ""
        isBordered = false
        setAccessibilitySubrole(.switch)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let background = state == .on ? NSColor.controlAccentColor : .quaternaryLabelColor
        (isEnabled ? background : background.withSystemEffect(.disabled)).setFill()
        let pill = NSBezierPath(roundedRect: track, xRadius: 11, yRadius: 11)
        pill.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.labelColor.setStroke()
            pill.lineWidth = 1
            pill.stroke()
        }
        let thumb = NSRect(x: state == .on ? track.maxX - 21 : track.minX + 1,
                           y: track.minY + 1, width: 20, height: 20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.6).setFill()
        NSBezierPath(ovalIn: thumb).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: track, xRadius: 11, yRadius: 11).fill()
    }
}
