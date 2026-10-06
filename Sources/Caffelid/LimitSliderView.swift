import AppKit

@MainActor
final class LimitSliderView: NSView {
    enum Kind { case battery, temperature }
    private let kind: Kind
    private let valueLabel = MenuTextField(labelWithString: "")
    private let currentLabel = MenuTextField(labelWithString: "")
    private let slider = NSSlider()
    var onChange: ((Int) -> Void)?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 306, height: 80))
        let title = Strings.text(kind == .battery ? "limit.battery" : "limit.temperature")
        let titleLabel = MenuTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 18, y: 56, width: 175, height: 18)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        valueLabel.frame = NSRect(x: 185, y: 56, width: 103, height: 18)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        currentLabel.frame = NSRect(x: 18, y: 7, width: 270, height: 16)
        currentLabel.font = .systemFont(ofSize: 11)
        currentLabel.textColor = .secondaryLabelColor
        slider.frame = NSRect(x: 17, y: 25, width: 272, height: 27)
        slider.minValue = 0
        slider.maxValue = kind == .battery ? 14 : 6
        slider.numberOfTickMarks = Int(slider.maxValue) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel(title)
        slider.setAccessibilityHelp(Strings.text(kind == .battery ? "limit.battery.help" : "limit.temperature.help"))
        [titleLabel, valueLabel, slider, currentLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) { nil }

    func update(step: Int, current: String, enabled: Bool) {
        slider.integerValue = step
        slider.isEnabled = enabled
        let value = Self.value(kind: kind, step: step)
        if valueLabel.stringValue != value { valueLabel.stringValue = value }
        if currentLabel.stringValue != current { currentLabel.stringValue = current }
        slider.setAccessibilityValueDescription(valueLabel.stringValue)
    }

    @objc private func changed() {
        valueLabel.stringValue = Self.value(kind: kind, step: slider.integerValue)
        onChange?(slider.integerValue)
    }

    private static func value(kind: Kind, step: Int) -> String {
        if kind == .battery { return step == 0 ? Strings.text("limit.off") : "\(step * 5)%" }
        return step == 6 ? Strings.text("limit.off") : "\(75 + step * 5) °C"
    }
}
