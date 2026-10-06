<p align="center">
  <img src="docs/assets/caffelid.png" width="112" height="112" alt="Caffelid coffee cup icon">
</p>

# Caffelid

**Keep your Mac awake with the lid closed. Let the display sleep.**

A small, native macOS menu bar app. One coffee cup, a switch, and configurable
battery and temperature limits. Free and open source under the [MIT license](LICENSE).

**Apple Silicon · macOS 13+ · English / Italiano · Developer ID signed and notarized**

[Guida in italiano](docs/README.it.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) ·
[Build from source](CONTRIBUTING.md) · [How it works](docs/ARCHITECTURE.md)

## Download and install

1. Download [**Caffelid.dmg**](https://github.com/Lab271-Agency/Caffelid/releases/latest/download/Caffelid.dmg) from the [latest release](https://github.com/Lab271-Agency/Caffelid/releases/latest).
2. Open the DMG and drag **Caffelid** into **Applications**.
3. Open the app. Click the coffee cup in the menu bar and enable the switch.
4. On the first activation, follow the prompt to allow **Caffelid** in
   **System Settings → General → Login Items & Extensions → Allow in the Background**.
   The wording varies by macOS version. Approve the administrator request on your Mac.

The support service is included. There is no separate installer or package to
download. Later activations use the approved service without asking for your
password again. You do not need Xcode or an Apple Developer account to use the app.
Keep Caffelid in Applications. The app has no Dock icon or main window.

## Everyday use

| Control | What it does |
| --- | --- |
| **Enabled / Disabled** | Enables or stops sleep prevention. The coffee cup fills when enabled. |
| **Battery limit** | Restores sleep at or below the selected percentage, while on battery with the lid closed. |
| **Temperature limit** | Restores sleep after 10 continuous seconds at or above the selected CPU/GPU temperature, with the lid closed. |
| **Launch at Login** | Opens Caffelid when you sign in. Every launch starts **disabled**. |
| **Quit** | Restores sleep and closes the app. |

Your limits and login preference are saved. If an enabled limit is already
reached, activation is blocked. Caffelid never reactivates itself after a limit
clears. The interface follows the system language, with English as the fallback.

### Default limits

- **Battery: 10%.** Choose Disabled or **5–70%** in 5% steps. This limit does not
  apply when a power adapter supplies the Mac.
- **Temperature: 95 °C.** Choose **75–100 °C** in 5 °C steps, or a separate Disabled
  position. Higher readings do not restart the 10-second countdown; cooling below
  the threshold resets it.

The temperature is the highest available CPU/GPU sensor reading, not the case
temperature. If data for an enabled limit is unavailable, activation is blocked. If it
remains unavailable for 10 seconds while enabled with the lid closed, sleep is restored.

## What changes on your Mac

Caffelid uses the system's sleep-disable setting through a macOS-managed privileged
service. Turning it off, quitting, losing the app connection, or restarting the
service restores normal sleep. Battery and display timers, brightness, and the
power adapter's **“Prevent automatic sleeping … when the display is off”** option
are left unchanged.

With the lid closed, Caffelid requests display sleep. If an external display is
connected, it leaves display management to macOS, because the display-sleep
command would switch off all displays. Sleep prevention remains enabled.

The app makes **no network requests**, includes no analytics, and stores no
passwords. Its background permission is separate from Launch at Login.

## Compatibility

The V1 download contains **arm64 binaries for Apple Silicon Macs**. macOS 13 is
the deployment minimum; Intel Macs are not supported by this download.

Development and physical checks were performed on a **MacBook Pro with M1 Pro**.
An additional MacBook Pro with M1 was used for field testing. The final build was
confirmed working by the user; this is not validation of every model or macOS
version. Temperature sensing relies on an undocumented AppleSMC interface, and
sensor availability can vary. See [verification details](docs/TESTING.md).

## Updates and removal

**Update:** open the lid, disable and quit Caffelid, then replace the app in
Applications with the new copy from the DMG. Your preferences are retained.

**Remove:** open the lid, disable Caffelid, turn off Launch at Login, and quit.
Turn off Caffelid's background permission in System Settings, then move the app
to the Trash. macOS can retain a historical background entry after removal.

If activation fails, start with [troubleshooting](docs/TROUBLESHOOTING.md).
For bugs, include your app version, Mac model, exact macOS version and build, and
steps to reproduce. See [SECURITY.md](SECURITY.md) for security reports.

## Development

Swift and C, using AppKit, ServiceManagement, IOKit, and Security.framework.
No third-party runtime packages.

```sh
bash Scripts/test.sh
swift build -c release
```

Tests use isolated fake power commands; they do not change your Mac's sleep
settings. A runnable app bundle requires an Apple-issued signing identity.
See [CONTRIBUTING.md](CONTRIBUTING.md) and the [release guide](docs/RELEASING.md).

## License and acknowledgements

Copyright © 2026 Michele Pagani. Licensed under [MIT](LICENSE).
The release's Apple signing identity is separate from the source copyright.

Apple's [PowerManagement source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
documents the sleep setting used here.
[smctemp](https://github.com/narugit/smctemp) is a reference for AppleSMC protocol
and sensor research; it is not a bundled dependency. Technical references are
listed in [the architecture guide](docs/ARCHITECTURE.md).
