# Troubleshooting

## First activation needs approval

Keep the app in Applications. Enable Caffelid under **System Settings → General →
Login Items & Extensions → Allow in the Background** (wording varies by macOS).
Approve the administrator prompt on the Mac. This is separate from Launch at
Login. An approved idle support service is normal when the main switch is off.

## Activation is blocked by a limit

Check the readings below the sliders. Battery at or below its enabled threshold
blocks activation only on battery; temperature at or above its threshold blocks
activation immediately. A required reading that is unavailable also blocks it.
Wait for the limit to clear or intentionally change the corresponding slider.
Caffelid does not reactivate itself.

## Support cannot be reached after an update or reinstall

1. Open the lid. Disable and quit Caffelid.
2. Check that the current app is in Applications and its background permission
   is enabled. Do not run it from inside the DMG.
3. Reopen the app and try again. If the service is still unavailable, restart
   the Mac with the lid open and retry.

For a read-only diagnostic:

```sh
/Applications/Caffelid.app/Contents/MacOS/Caffelid --check
/Applications/Caffelid.app/Contents/MacOS/Caffelid --sensors
```

Review output before including it in a bug report. Do not share credentials or
unrelated system logs.

Explicit service repair changes the registration and may require approval again.
Open the lid, disable and quit the app first:

```sh
/Applications/Caffelid.app/Contents/MacOS/Caffelid --test-cycle --repair-support
```

This also performs a real activation/deactivation cycle; it is not read-only.

## A historical background entry remains

macOS can retain a record after an app is removed. Earlier Lungo/Caffelid betas
can therefore leave an additional entry. Disable the removed beta's entry and
keep the current entry approved. Do not reset all background items or disable
system security protections to remove a historical label; that affects other apps.

## The Mac remains unable to sleep

Open the lid and disable or quit Caffelid. If the app/service cannot be used,
this manual recovery restores the sleep-disable setting:

```sh
sudo /usr/bin/pmset -a disablesleep 0
```

Enter the password only in your own Terminal. This does not change the separate
power adapter “Prevent automatic sleeping … when the display is off” option.
Other apps or normal clamshell behavior can also keep the Mac awake.

## Verify the lid-closed behavior

Use the physical test in [TESTING.md](TESTING.md). An Enabled switch or
`SleepDisabled=1` confirms the setting, not continuous execution with the lid closed.
