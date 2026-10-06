import Foundation
import CoreFoundation

struct SafetyLimits: Equatable, Sendable {
    var batteryPercent: Int? = 10
    var temperatureCelsius: Int? = 95
}

enum PowerSupply: Equatable, Sendable { case battery, adapter, unknown }

struct HardwareSnapshot: Sendable {
    var batteryPercent: Double?
    var powerSupply: PowerSupply = .unknown
    var temperatureCelsius: Double?
    var temperatureSensorCount = 0
}

enum SafetyReason: String, Sendable {
    case battery, temperature, batteryUnavailable, temperatureUnavailable
    var message: String { Strings.text("safety.\(rawValue)") }
}

struct SafetyPolicy {
    private var hotSince: TimeInterval?
    private var missingBatterySince: TimeInterval?
    private var missingTemperatureSince: TimeInterval?
    private var lastSample: TimeInterval?
    private var lastLimits: SafetyLimits?

    static func batteryBlock(_ snapshot: HardwareSnapshot, limits: SafetyLimits) -> SafetyReason? {
        guard let limit = limits.batteryPercent, snapshot.powerSupply != .adapter else { return nil }
        guard snapshot.powerSupply == .battery, let percent = snapshot.batteryPercent,
              percent.isFinite, (0...100).contains(percent) else { return .batteryUnavailable }
        return percent <= Double(limit) ? .battery : nil
    }

    static func temperatureBlock(_ snapshot: HardwareSnapshot, limits: SafetyLimits) -> SafetyReason? {
        guard let limit = limits.temperatureCelsius else { return nil }
        guard let temperature = snapshot.temperatureCelsius,
              temperature.isFinite, temperature > 0, temperature <= 150 else { return .temperatureUnavailable }
        return temperature >= Double(limit) ? .temperature : nil
    }

    static func activationBlock(_ snapshot: HardwareSnapshot, limits: SafetyLimits) -> SafetyReason? {
        batteryBlock(snapshot, limits: limits) ?? temperatureBlock(snapshot, limits: limits)
    }

    mutating func reset() {
        hotSince = nil
        missingBatterySince = nil
        missingTemperatureSince = nil
        lastSample = nil
        lastLimits = nil
    }

    mutating func deactivationReason(_ snapshot: HardwareSnapshot, limits: SafetyLimits,
                                    active: Bool, lidClosed: Bool, now: TimeInterval) -> SafetyReason? {
        guard active, lidClosed else { reset(); return nil }
        if limits != lastLimits || lastSample.map({ now < $0 || now - $0 > 2.5 }) == true {
            reset()
        }
        lastLimits = limits
        lastSample = now
        let battery = Self.batteryBlock(snapshot, limits: limits)
        if battery == .battery { return .battery }
        if Self.elapsed(condition: battery == .batteryUnavailable, since: &missingBatterySince, now: now) {
            return .batteryUnavailable
        }
        let temperature = Self.temperatureBlock(snapshot, limits: limits)
        if Self.elapsed(condition: temperature == .temperature, since: &hotSince, now: now) {
            return .temperature
        }
        if Self.elapsed(condition: temperature == .temperatureUnavailable, since: &missingTemperatureSince, now: now) {
            return .temperatureUnavailable
        }
        return nil
    }

    private static func elapsed(condition: Bool, since: inout TimeInterval?, now: TimeInterval) -> Bool {
        guard condition else { since = nil; return false }
        if since == nil { since = now }
        return now - (since ?? now) >= 10
    }
}

@MainActor
final class SafetyPreferences {
    private let defaults: UserDefaults
    private(set) var batteryStep: Int
    private(set) var temperatureStep: Int
    var limits: SafetyLimits {
        SafetyLimits(batteryPercent: batteryStep == 0 ? nil : batteryStep * 5,
                     temperatureCelsius: temperatureStep == 6 ? nil : 75 + temperatureStep * 5)
    }

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        // Preserve only the two validated slider choices from the pre-release identity.
        for (key, maximum, fallback) in [("batteryLimitStep", 14, 2), ("temperatureLimitStep", 6, 4)] {
            if defaults.object(forKey: key) == nil, let value = legacyDefaults?.object(forKey: key) {
                defaults.set(Self.savedStep(value, maximum: maximum, fallback: fallback), forKey: key)
            }
        }
        self.defaults = defaults
        batteryStep = Self.savedStep(defaults.object(forKey: "batteryLimitStep"), maximum: 14, fallback: 2)
        temperatureStep = Self.savedStep(defaults.object(forKey: "temperatureLimitStep"), maximum: 6, fallback: 4)
    }

    func setBatteryStep(_ step: Int) {
        guard (0...14).contains(step) else { return }
        batteryStep = step
        defaults.set(step, forKey: "batteryLimitStep")
    }

    func setTemperatureStep(_ step: Int) {
        guard (0...6).contains(step) else { return }
        temperatureStep = step
        defaults.set(step, forKey: "temperatureLimitStep")
    }

    private static func savedStep(_ value: Any?, maximum: Int, fallback: Int) -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue,
              (0...Double(maximum)).contains(number.doubleValue) else { return fallback }
        return number.intValue
    }
}
