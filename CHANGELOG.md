# Changelog

## 1.0.0

First public release, build 19. Sleep behavior is unchanged from build 18;
build 19 adds original app icon artwork for distribution.

- Native macOS menu bar app with a coffee cup and no Dock icon.
- Lid-closed sleep prevention with display sleep and external-display handling.
- Battery cutoff: 10% by default, configurable from 5% to 70% or disabled.
- CPU/GPU temperature cutoff: 95 °C by default, configurable from 75 °C to
  100 °C or disabled, with a continuous 10-second grace period.
- Activation checks and recovery when an enabled sensor is unavailable.
- Optional Launch at Login; every launch starts disabled.
- Saved limits, system-accent switches, and English/Italian localization.
- Included macOS-managed support service, approved once by the user.
- Sleep restoration on deactivation, quit, client disconnect, and service restart.
- Developer ID signed and Apple notarized app and DMG for Apple Silicon.

The internal app identity is `app.caffelid.desktop`. Development builds named
Lungo and early Caffelid betas were not public releases.
