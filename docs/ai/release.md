# Release

Before a release:

0. For a developer-only local install, use:

   ```sh
   make install-local
   ```

   This builds and opens a local Xcode-signed Release app without sharing Developer ID keys.

1. Check the current app version, git-derived build number, and package path:

   ```sh
   make version
   ```

2. Build, test, package, and verify the internal zip with:

   ```sh
   make release
   ```

   The package is written to `dist/TimeClockBar-<version>-internal.zip`.

3. For local releases, tag the release commit when the package is accepted:

   ```sh
   make tag-version
   ```

4. For GitHub Releases, merge the release commits to `main`. GitHub Actions computes the version from commits, runs `make release`, creates the `v<version>` tag, and uploads the zip to the release. The `Release` workflow can also be run manually when needed.

5. Run the app from a clean install or clean user defaults when practical.
6. Verify login, menu-bar status, reminders, hotkey, daily report, About window, and launch-at-login behavior.
7. Confirm code signing and `TimeClockBar/Resources/TimeClockBar.entitlements` in Xcode before distribution.

`make install-local` is for developers building on their own Macs. `make release` creates an internal ad-hoc signed package. Developer ID signing, hardened runtime, notarization, and stapling are still required for warning-free distribution to other Macs.

Versioning rule: `MARKETING_VERSION` is passed into Xcode from the computed conventional-commit version. `CURRENT_PROJECT_VERSION` is passed into Xcode builds from `git rev-list --count HEAD`, so the app build number tracks git history automatically.

`scripts/next-version.sh` computes the release version from conventional commits since the latest `v*` tag. Breaking changes bump major, `feat:` bumps minor, and `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, and `revert:` bump patch. `scripts/test-next-version.sh` covers that bump behavior.

GitHub Actions:
- `CI` runs version checks and a Debug build on pushes to `main` and pull requests.
- `Release` runs automatically on pushes to `main`, skips when the computed version already matches the latest tag, and creates the tag plus GitHub Release asset when there is a new version.

Run `make test` locally before release changes. The app currently targets macOS 26.5, and GitHub-hosted macOS 26 runners can lag behind that OS version, which prevents hosted XCTest execution.
