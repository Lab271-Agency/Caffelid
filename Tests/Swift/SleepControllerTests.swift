import Testing
@testable import Caffelid

@Test func readsConfirmedSystemSetting() {
    #expect(SleepController.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t1\n") == true)
    #expect(SleepController.parseSleepDisabled(" SleepDisabled 0\n sleep 0\n") == false)
    #expect(SleepController.parseSleepDisabled(" sleep 0\n") == nil)
    #expect(SleepController.parseSleepDisabled(" SleepDisabled 2\n") == nil)
    #expect(SleepController.parseSleepDisabled(" SleepDisabled 1 unexpected\n") == nil)
}

