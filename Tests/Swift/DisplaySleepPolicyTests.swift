import Testing
@testable import Caffelid

@Test func sleepsDisplayOncePerClosureWhileActive() {
    var policy = DisplaySleepPolicy()
    let decisions = [
        policy.shouldSleep(active: true, lidClosed: false, hasExternalDisplay: false),
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: false),
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: false),
        policy.shouldSleep(active: true, lidClosed: false, hasExternalDisplay: false),
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: false)
    ]
    #expect(decisions == [false, true, false, false, true])
}

@Test func handlesActivationWithClosedLidAndCancelsOnDeactivation() {
    var policy = DisplaySleepPolicy()
    let decisions = [
        policy.shouldSleep(active: false, lidClosed: true, hasExternalDisplay: false),
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: false),
        policy.shouldSleep(active: false, lidClosed: true, hasExternalDisplay: false),
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: false)
    ]
    #expect(decisions == [false, true, false, true])
}

@Test func preservesExternalDisplayAndReactsToDisconnection() {
    var policy = DisplaySleepPolicy()
    let decisions = [
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: true),
        policy.shouldSleep(active: true, lidClosed: true, hasExternalDisplay: false)
    ]
    #expect(decisions == [false, true])
}
