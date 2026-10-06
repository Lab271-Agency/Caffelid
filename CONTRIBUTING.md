# Contributing to Caffelid

Bug reports, hardware compatibility reports, translations, and focused pull
requests are welcome. Keep the menu simple and preserve accessibility.

## Set up

Use macOS with Xcode 26 or later, Swift 6.2+, and Python 3. Open `Package.swift` in
Xcode or use the terminal. There are no external package dependencies.
The newer SDK supplies the concurrency annotations needed by ServiceManagement;
this build requirement does not change the app’s macOS 13 deployment minimum.

```sh
bash Scripts/test.sh
swift build -c release
```

Unsigned compilation and tests require no Apple Developer membership. Helper
integration tests sign a test client ad hoc and use temporary sockets, files,
and fake commands. They never operate the installed service or real power state.

To create a runnable app bundle, install an Apple-issued signing certificate
with its private key in your Keychain:

```sh
CAFFELID_SIGNING_IDENTITY="certificate identity or fingerprint" bash Scripts/build.sh
```

The build selects Developer ID Application first, then Apple Development if no
identity is supplied. Ad hoc signatures cannot run the production support
service. The build writes an app, ZIP, and DMG to `dist/`; it does not install them.
Public downloads require Developer ID signing and notarization; see
[RELEASING.md](docs/RELEASING.md).

## Make a change

1. Check the relevant implementation and [architecture](docs/ARCHITECTURE.md).
2. Keep changes focused. Preserve the final app/service identity and signing
   checks; never add a caller-controlled privileged command or executable path.
3. Keep English and Italian strings in sync. Use native accessibility labels
   and roles. Add meaningful tests for changes to sleep, limits, or recovery.
4. Run tests and release compilation. Explain the behavior change, checks run,
   and any verification you could not perform in your pull request.

GUI code is in `Sources/Caffelid`; the root helper is in `Sources/CaffelidHelper`.
IPC/signature checks and the read-only temperature reader are separate C targets.
Tests live in `Tests`.

GitHub CI runs isolated tests and compilation without signing credentials. It
cannot validate administrator approval, lid behavior, or physical temperatures.
For manual validation, see [TESTING.md](docs/TESTING.md).

## Reports

Use the bug report form for ordinary defects, with the exact macOS version/build
and app version. Review diagnostic output before sharing it; omit passwords,
signing keys, personal paths, and unrelated logs. Follow [SECURITY.md](SECURITY.md)
for suspected privilege or signature-validation vulnerabilities.
