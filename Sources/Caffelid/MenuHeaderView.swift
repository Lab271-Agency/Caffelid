import AppKit

@MainActor
final class MenuHeaderView: NSView {
    override var allowsVibrancy: Bool { false }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 306, height: 32))
        let label = NSTextField(labelWithString: "Caffelid")
        label.frame = NSRect(x: 18, y: 7, width: 270, height: 20)
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }
}
