# Release

Before a release:

1. Build the Release configuration in Xcode or with:

   ```sh
   xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Release build
   ```

2. Run the app from a clean install or clean user defaults when practical.
3. Verify login, menu-bar status, reminders, hotkey, daily report, and launch-at-login behavior.
4. Confirm code signing and entitlements in Xcode before distribution.

There is no automated deployment pipeline documented in this repository yet.

