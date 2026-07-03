# Release

Before a release:

1. Build the Release configuration in Xcode or with:

   ```sh
   xcodebuild -project TimeClockBar.xcodeproj -scheme TimeClockBar -configuration Release build
   ```

2. Run the app from a clean install or clean user defaults when practical.
3. Verify login, menu-bar status, reminders, hotkey, daily report, About window, and launch-at-login behavior.
4. Confirm `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `TimeClockBar.xcodeproj/project.pbxproj`.
5. Confirm code signing and `TimeClockBar/Resources/TimeClockBar.entitlements` in Xcode before distribution.

There is no automated deployment pipeline documented in this repository yet.
