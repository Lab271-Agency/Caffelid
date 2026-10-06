# Release guide

## Local checks

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `Resources/Info.plist` before distributing a new build. Update the changelog
   and release notes. Preserve app/helper identifiers and the signing team.
2. Run `bash Scripts/test.sh` and `swift build -c release` on macOS.
3. Review the source diff and files selected for Git. Exclude credentials,
   `.build/`, `dist/`, and local investigation notes. App icon artwork is original;
   SF Symbols are used only as in-app interface controls, not as app icons.

## Build, sign, and notarize

Use a **Developer ID Application** certificate with its private key in Keychain.
Configure a notarytool Keychain profile interactively, keeping passwords out of
command arguments and source control:

```sh
xcrun notarytool store-credentials Caffelid
CAFFELID_SIGNING_IDENTITY="Developer ID certificate fingerprint" bash Scripts/build.sh
CAFFELID_SIGNING_IDENTITY="Developer ID certificate fingerprint" bash Scripts/notarize.sh Caffelid
bash Scripts/verify-release.sh
```

The notarization script submits the app, staples its ticket, rebuilds/signs the
DMG with that app, submits/staples the DMG, and writes `dist/SHA256SUMS`. Exit 75
means Apple is still processing; run the same command again to resume. Receipts
remain under `.build/notarization/`. Never upload Keychain data or those local logs.

The verification script checks the expected versions/architecture, Developer ID
signatures and common team, stapled tickets, Gatekeeper assessments, disk image
integrity, checksums, and matching app files in the ZIP and mounted read-only DMG.
It does not launch the app, register services, or change power settings.

## Manual acceptance

Use [TESTING.md](TESTING.md) to check real approval and lid behavior. Tests and
Apple notarization do not establish compatibility on every Mac. Record what
was verified without advertising untested hardware as supported.

## Publish on GitHub

Use a public repository named **Caffelid**, with description:

> Native macOS menu bar app that keeps your Mac awake with the lid closed, with battery and temperature limits.

Suggested topics: `macos`, `apple-silicon`, `menu-bar`, `swift`, `c`, `sleep`,
`clamshell`, `open-source`.

1. Push the reviewed source to `main`. Check the first CI run before publishing.
2. Enable **Private vulnerability reporting** under the repository's security
   settings so the channel described in `SECURITY.md` is available.
3. Create a release for tag **v1.0.0** from the reviewed commit. Use
   [the prepared release notes](releases/v1.0.0.md).
4. Attach exactly `Caffelid.dmg`, `Caffelid.zip`, and `SHA256SUMS` from verified
   `dist/`. The DMG is the recommended download; ZIP is an alternative.
5. Re-download the published DMG and verify its checksum and normal opening
   flow. Add a direct latest-download link to the README once the repository URL
   and release exist.

Do not recreate the app or DMG after final checksum/signature verification. A
rebuild invalidates acceptance and requires notarization and verification again.
Once a build has been shared, increment its build number before replacing assets.

Source copyright belongs to the project author. The Apple team signing the
download is a separate distribution identity; do not publish its credentials.

References: [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[GitHub private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository),
[Apple SF Symbols guidance](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).
