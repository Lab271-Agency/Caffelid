# Architecture

## User process

`AppDelegate` owns the AppKit menu and operation state. Native menu views expose
accessible switches, sliders, and labels. Translations are bundled in English
and Italian. `SafetyPreferences` validates persisted values; `SafetyPolicy`
handles activation checks and monotonic, continuous limit timing.

`HardwareMonitor` reads battery/power-source data through IOPowerSources and
CPU/GPU temperature through `CaffelidSensors`. The AppleSMC reader only enumerates
keys, reads key information, and reads values. It cannot write fan or power
settings. It selects the highest valid supported CPU/GPU reading and reports
unavailable data explicitly.

`LidMonitor` uses IOKit notifications. The display policy schedules
`/usr/bin/pmset displaysleepnow` as the user after lid closure while enabled.
Opening the lid or disabling cancels a pending request. External displays bypass
this request because it affects every display.

## Privileged service

The production identity is `app.caffelid.desktop`; the daemon is
`app.caffelid.desktop.sleep-service`. SMAppService registers its bundled launchd
plist and executable. macOS manages initial administrator approval.

The app connects to a launchd-owned Unix socket. `CaffelidIPC` obtains the peer's
kernel audit token and validates its Security.framework code signature against
an exact app identifier, an Apple anchor, and the helper's own signing team.
The protocol has fixed operations and no executable-path or command-string input.

The only privileged power commands are:

```sh
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

A root-owned lock prevents concurrent helpers from owning the sleep setting.
The GUI checks actual power state before confirming a toggle. The daemon retries
restoration and restores sleep after connection loss, termination, and restart.
Activation does not automatically unregister/re-register an approved service.

The battery and temperature policies run in the GUI once per second, including
while the menu is open. Fresh readings are checked before and after activation.
The root helper handles connection recovery rather than reading sensors.

## Development migration

Lungo and early Caffelid betas used different identities. The helper retires only
their exact legacy jobs. Packaged legacy files are checked for ownership,
permissions, paths, and identity before removal. The shared lock prevents
concurrent power-setting changes during migration.

Only valid battery/temperature preferences migrate from `app.caffelid.mac` when
new keys do not exist. Login and background permission are managed separately.
Future releases must preserve the final app/helper identifiers and signing team.

## Boundaries and references

`disablesleep` and AppleSMC availability can vary across macOS and hardware.
The policy is not a hardware thermal controller. Apple notarization does not
certify lid or temperature behavior on every Mac. Physical testing is separate
from isolated automated tests. The app contains no telemetry or network code;
release tools use Apple's timestamp/notary services.

- [Apple PowerManagement / pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Apple: Getting started with SMAppService](https://developer.apple.com/forums/thread/802443)
- [Apple: Service signing requirements](https://developer.apple.com/forums/thread/799910)
- [Apple: Re-registration timing](https://developer.apple.com/forums/thread/783539)
- [Apple: Code signing requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
- [smctemp: AppleSMC protocol and sensor reference](https://github.com/narugit/smctemp)
