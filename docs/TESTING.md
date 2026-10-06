# Testing and compatibility

## Isolated automated tests

```sh
bash Scripts/test.sh
```

The suite includes 18 Swift tests, one C sensor test program, and 24 helper
integration tests. It covers limit boundaries, adapter exceptions, continuous
10-second timing, missing data, preferences, display policy, audit-token and
signature checks, failed commands, retries, exclusive ownership, disconnect,
termination, restart, and scoped legacy migration.

C tests use AddressSanitizer and UndefinedBehaviorSanitizer. Integration tests
use temporary sockets/files and fake power and migration commands. They never
change real power settings or installed services. Signing credentials are not
required. Tests and release compilation are configured in GitHub CI.

## Quick physical lid test

Use a terminal clock to check whether a process continues with the lid closed.
Disconnect external displays and docks so normal clamshell mode does not confound
the result. Leave the Mac on a desk with ventilation.

1. With Caffelid disabled, run in Terminal:

   ```sh
   while true; do date '+%H:%M:%S'; sleep 2; done
   ```

2. Close the lid for 30 seconds, reopen it, and wait for the next line. There
   should be a gap around the sleep period. Other software can prevent sleep;
   this step establishes a baseline.
3. Enable Caffelid with limits clear and repeat. Lines should continue at roughly
   two-second intervals during closure. The display should be off while closed.
4. Open the lid, disable Caffelid, and repeat to verify sleep is restored.
   Stop the clock with **Control-C**.

If the baseline already keeps printing, remove the source of sleep prevention
before drawing a conclusion. One test does not establish every power scenario.

## Manual release checks

- Fresh DMG copy into Applications, normal opening confirmation, first support
  approval, repeated activation without another password prompt.
- Quit while enabled, reopen disabled, and restart with Launch at Login selected.
- Update and delete/reinstall with valid preferences and approval retained.
- English/Italian labels, all slider positions, system accent, accessibility,
  menu open during sampling, and repeated toggle operations.
- Battery activation blocking on battery and adapter exception. Choose a limit
  above current charge; no need to drain the battery deliberately.
- Temperature blocking, spikes, missing readings, and recovery. Use simulated
  tests for the countdown; do not heat a Mac deliberately to trigger a cutoff.
- Display sleep and external-display handling.

The opt-in `--test-cycle` changes the real sleep flag with the lid open and restores
it; it does not validate execution while closed. It requires the GUI disabled and
quit. `--check` and `--sensors` are read-only.

## V1 evidence and limits

| Area | Evidence |
| --- | --- |
| Automated logic | Isolated Swift/C suite and optimized source compilation on the development Mac. |
| Service | Build 18 approval, repeated native cycles, quit/reopen, and DMG reinstall on the M1 Pro development Mac. |
| Power/display profiles | Unchanged before and after native activation/deactivation cycles. |
| Physical lid/display and login | Tested during development on a MacBook Pro M1 Pro; final-build restart remains a separate check. |
| Additional hardware | MacBook Pro M1 used for field testing. Final user report on 2026-10-06: everything works now; a detailed per-feature result was not recorded. |
| Clean local install | App data reset, old jobs removed, final DMG installed with synthetic quarantine; opening, approval, and activation confirmed. Not a new Mac or an actual GitHub download. |
| OS versions | Development Mac: macOS 26.6.1. Field report: macOS 27.0 (26A428). macOS 13–15 are deployment targets, not physically verified versions. |

Public binaries target Apple Silicon and macOS 13+. Intel, other chip generations,
every OS release, and physical high-temperature/low-battery cutoff are not
established by these checks. Include exact model, OS/build, power source, and
display connections when reporting compatibility.

Build 19 replaces the app icon with original artwork and updates the bundle
build number. GUI/helper source and sleep policies are unchanged from build 18;
the field tests above apply to that functionality. Build 19 distribution checks
are performed separately with `Scripts/verify-release.sh`.
