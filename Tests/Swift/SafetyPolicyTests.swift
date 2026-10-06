import Foundation
import Testing
@testable import Caffelid

private func reading(battery: Double? = 50, power: PowerSupply = .battery,
                     temperature: Double? = 60) -> HardwareSnapshot {
    HardwareSnapshot(batteryPercent: battery, powerSupply: power, temperatureCelsius: temperature)
}

@Test func batteryBlocksAtOrBelowLimitOnlyOnBattery() {
    #expect(SafetyPolicy.activationBlock(reading(battery: 10), limits: SafetyLimits()) == .battery)
    #expect(SafetyPolicy.activationBlock(reading(battery: 9.9), limits: SafetyLimits()) == .battery)
    #expect(SafetyPolicy.activationBlock(reading(battery: 10.1), limits: SafetyLimits()) == nil)
    #expect(SafetyPolicy.activationBlock(reading(battery: 1, power: .adapter), limits: SafetyLimits()) == nil)
    #expect(SafetyPolicy.activationBlock(reading(battery: nil, power: .adapter), limits: SafetyLimits()) == nil)
    #expect(SafetyPolicy.activationBlock(reading(battery: 1), limits: SafetyLimits(batteryPercent: nil)) == nil)
}

@Test func temperatureBlocksActivationImmediatelyIncludingExactThreshold() {
    #expect(SafetyPolicy.activationBlock(reading(temperature: 95), limits: SafetyLimits()) == .temperature)
    #expect(SafetyPolicy.activationBlock(reading(temperature: 100), limits: SafetyLimits()) == .temperature)
    #expect(SafetyPolicy.activationBlock(reading(temperature: 94.99), limits: SafetyLimits()) == nil)
    #expect(SafetyPolicy.activationBlock(reading(temperature: 99.99), limits: SafetyLimits(temperatureCelsius: 100)) == nil)
    #expect(SafetyPolicy.activationBlock(reading(temperature: 100), limits: SafetyLimits(temperatureCelsius: 100)) == .temperature)
    #expect(SafetyPolicy.activationBlock(reading(temperature: 120), limits: SafetyLimits(temperatureCelsius: nil)) == nil)
}

@Test func eitherLimitBlocksIndependently() {
    #expect(SafetyPolicy.activationBlock(reading(battery: 5, temperature: 100), limits: SafetyLimits()) == .battery)
    #expect(SafetyPolicy.activationBlock(reading(battery: 5, power: .adapter, temperature: 100), limits: SafetyLimits()) == .temperature)
    #expect(SafetyPolicy.activationBlock(reading(battery: 5, temperature: 100),
        limits: SafetyLimits(batteryPercent: nil, temperatureCelsius: nil)) == nil)
}

@Test func invalidOrUnavailableReadingsDoNotBypassEnabledLimits() {
    for value: Double? in [nil, .nan, .infinity, -1, 101] {
        #expect(SafetyPolicy.activationBlock(reading(battery: value), limits: SafetyLimits()) == .batteryUnavailable)
    }
    #expect(SafetyPolicy.activationBlock(reading(power: .unknown), limits: SafetyLimits()) == .batteryUnavailable)
    for value: Double? in [nil, .nan, .infinity, 0, -1, 151] {
        #expect(SafetyPolicy.activationBlock(reading(temperature: value), limits: SafetyLimits()) == .temperatureUnavailable)
    }
    #expect(SafetyPolicy.activationBlock(reading(battery: nil, power: .unknown, temperature: nil),
        limits: SafetyLimits(batteryPercent: nil, temperatureCelsius: nil)) == nil)
}

@Test func batteryDeactivatesWithClosedLidImmediately() {
    var policy = SafetyPolicy()
    #expect(policy.deactivationReason(reading(battery: 10), limits: SafetyLimits(), active: true,
        lidClosed: false, now: 0) == nil)
    #expect(policy.deactivationReason(reading(battery: 10), limits: SafetyLimits(), active: true,
        lidClosed: true, now: 1) == .battery)
    #expect(policy.deactivationReason(reading(battery: 1, power: .adapter), limits: SafetyLimits(), active: true,
        lidClosed: true, now: 2) == nil)
}

@Test func temperatureWaitsTenContinuousSecondsEvenAsItRises() {
    var policy = SafetyPolicy()
    for second in 0..<10 {
        #expect(policy.deactivationReason(reading(temperature: 95 + Double(second)), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 99), limits: SafetyLimits(),
        active: true, lidClosed: true, now: 10) == .temperature)
}

@Test func briefTemperatureSpikeAndCoolingResetCountdown() {
    var policy = SafetyPolicy()
    for second in 0..<9 {
        #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 94.9), limits: SafetyLimits(),
        active: true, lidClosed: true, now: 9) == nil)
    for second in 10..<20 {
        #expect(policy.deactivationReason(reading(temperature: 95), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 95), limits: SafetyLimits(),
        active: true, lidClosed: true, now: 20) == .temperature)
}

@Test(arguments: [false, true]) func openingLidOrDeactivatingResetsCountdown(openLid: Bool) {
    var policy = SafetyPolicy()
    for second in 0..<9 {
        #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
        active: openLid, lidClosed: !openLid, now: 9) == nil)
    for second in 10..<20 {
        #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
        active: true, lidClosed: true, now: 20) == .temperature)
}

@Test func changingThresholdAndDisablingLimitResetCountdown() {
    var policy = SafetyPolicy()
    for second in 0..<9 {
        #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    for second in 9..<19 {
        #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(temperatureCelsius: 100),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(temperatureCelsius: nil),
        active: true, lidClosed: true, now: 19) == nil)
}

@Test func observationGapDoesNotCountAsProvenOverheating() {
    var policy = SafetyPolicy()
    #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
        active: true, lidClosed: true, now: 0) == nil)
    for second in 30..<40 {
        #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(reading(temperature: 100), limits: SafetyLimits(),
        active: true, lidClosed: true, now: 40) == .temperature)
}

@Test(arguments: [SafetyReason.batteryUnavailable, .temperatureUnavailable])
func unavailableEnabledSensorRestoresSleepAfterTenSeconds(reason: SafetyReason) {
    var policy = SafetyPolicy()
    let missing = reason == .batteryUnavailable ? reading(battery: nil) : reading(temperature: nil)
    for second in 0..<10 {
        #expect(policy.deactivationReason(missing, limits: SafetyLimits(),
            active: true, lidClosed: true, now: Double(second)) == nil)
    }
    #expect(policy.deactivationReason(missing, limits: SafetyLimits(),
        active: true, lidClosed: true, now: 10) == reason)
}

@Test @MainActor func preferencesPersistAllStepsWithSeparateDisabledTemperaturePosition() throws {
    let suite = "app.caffelid.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = SafetyPreferences(defaults: defaults)
    #expect(preferences.limits == SafetyLimits())
    for step in 0...14 {
        preferences.setBatteryStep(step)
        #expect(SafetyPreferences(defaults: defaults).limits.batteryPercent == (step == 0 ? nil : step * 5))
    }
    for step in 0...6 {
        preferences.setTemperatureStep(step)
        #expect(SafetyPreferences(defaults: defaults).limits.temperatureCelsius == (step == 6 ? nil : 75 + step * 5))
    }
    preferences.setBatteryStep(15)
    preferences.setTemperatureStep(-1)
    #expect(preferences.limits == SafetyLimits(batteryPercent: 70, temperatureCelsius: nil))
}

@Test @MainActor func corruptPreferencesFallBackToDefaults() throws {
    let suite = "app.caffelid.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    for value: Any in [true, "5", 1.5, -1, 100] {
        defaults.set(value, forKey: "batteryLimitStep")
        defaults.set(value, forKey: "temperatureLimitStep")
        #expect(SafetyPreferences(defaults: defaults).limits == SafetyLimits())
    }
}

@Test @MainActor func betaPreferencesMigrateWithoutOverwritingNewChoices() throws {
    let suite = "app.caffelid.tests.\(UUID().uuidString)"
    let legacySuite = suite + ".beta"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let legacy = try #require(UserDefaults(suiteName: legacySuite))
    defer {
        defaults.removePersistentDomain(forName: suite)
        legacy.removePersistentDomain(forName: legacySuite)
    }
    legacy.set(3, forKey: "batteryLimitStep")
    legacy.set(6, forKey: "temperatureLimitStep")
    #expect(SafetyPreferences(defaults: defaults, legacyDefaults: legacy).limits ==
            SafetyLimits(batteryPercent: 15, temperatureCelsius: nil))
    defaults.set(2, forKey: "batteryLimitStep")
    legacy.set(14, forKey: "batteryLimitStep")
    #expect(SafetyPreferences(defaults: defaults, legacyDefaults: legacy).limits.batteryPercent == 10)
    defaults.removeObject(forKey: "temperatureLimitStep")
    legacy.set(true, forKey: "temperatureLimitStep")
    #expect(SafetyPreferences(defaults: defaults, legacyDefaults: legacy).limits.temperatureCelsius == 95)
}
