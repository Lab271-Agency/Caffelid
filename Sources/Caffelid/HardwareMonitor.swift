import Foundation
import IOKit.ps
import CaffelidSensors

private final class TemperatureReader {
    private let handle: OpaquePointer
    init?() {
        guard let handle = caffelid_temperature_reader_create() else { return nil }
        self.handle = handle
    }
    deinit { caffelid_temperature_reader_destroy(handle) }
    func read() -> (Double, Int)? {
        var value = 0.0
        var count = 0
        guard caffelid_temperature_read(handle, &value, &count) == 0 else { return nil }
        return (value, count)
    }
}

// The actor serializes SMC access off the main thread; the reader never escapes it.
actor HardwareMonitor {
    private var reader: TemperatureReader?
    private var lastOpenAttempt: TimeInterval = -.infinity

    func sample() -> HardwareSnapshot {
        var snapshot = Self.powerSnapshot()
        let now = ProcessInfo.processInfo.systemUptime
        if reader == nil, now - lastOpenAttempt >= 5 {
            lastOpenAttempt = now
            reader = TemperatureReader()
        }
        if let reading = reader?.read() {
            snapshot.temperatureCelsius = reading.0
            snapshot.temperatureSensorCount = reading.1
        } else {
            reader = nil // Reopen after a driver failure; never reuse stale values.
        }
        return snapshot
    }

    private static func powerSnapshot() -> HardwareSnapshot {
        var result = HardwareSnapshot()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return result }
        if let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            if type == kIOPSACPowerValue { result.powerSupply = .adapter }
            else if type == kIOPSBatteryPowerValue { result.powerSupply = .battery }
        }
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return result }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
                  maximum.doubleValue > 0 else { continue }
            let percent = current.doubleValue / maximum.doubleValue * 100
            if percent.isFinite, (0...100).contains(percent) { result.batteryPercent = percent }
            break
        }
        return result
    }
}
