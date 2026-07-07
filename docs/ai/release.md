# Release

Before a release:

0. For a developer-only local install, use:

   ```sh
   make install-local
   ```

   This builds and opens a local Xcode-signed Release app without sharing Developer ID keys.

1. Build, package, and verify the internal zip with:

   ```sh
   make release
   ```

   The package is written to `dist/TimeClockBar-1.0-internal.zip`.

2. Run the app from a clean install or clean user defaults when practical.
3. Verify login, menu-bar status, reminders, hotkey, daily report, About window, and launch-at-login behavior.
4. Confirm `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `TimeClockBar.xcodeproj/project.pbxproj`.
5. Confirm code signing and `TimeClockBar/Resources/TimeClockBar.entitlements` in Xcode before distribution.

`make install-local` is for developers building on their own Macs. `make release` creates an internal ad-hoc signed package. Developer ID signing, hardened runtime, notarization, and stapling are still required for warning-free distribution to other Macs.
