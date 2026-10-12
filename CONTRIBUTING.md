# Working on this fork

This fork keeps TailRemote a small, direct iPhone-to-Mac remote. Preserve its constraints: no hosted backend, no relay, no analytics, and passwords stored only in the device-local Keychain when Remember password is enabled.

This copy does not collect issues or pull requests for the original project. If your devices are not compatible, fork this repo and have your own agents make it work for your devices.

## Before you change the project

1. Keep each change focused on one problem.
2. Add or update tests for geometry, input, and connection-state changes.
3. Never commit hostnames, IP addresses, usernames, passwords, signing teams, provisioning profiles, or certificates.
4. Run the simulator test suite and record which physical devices you actually tried.

## Development setup

1. Install Xcode 16 or newer.
2. Install XcodeGen with `brew install xcodegen`.
3. Run `xcodegen generate` after changing `project.yml`.
4. Open `TailRemote.xcodeproj` and build the `TailRemote` scheme.

The checked-in bundle ID `com.example.tailremote` is a placeholder. Replace it with an ID you control before you install the app. Do not pass a global `PRODUCT_BUNDLE_IDENTIFIER` override: Xcode also applies it to package frameworks, which makes iOS reject duplicate bundle IDs. The upstream app's identifier, `com.waack.TailRemote`, belongs to that project.

The generated Xcode project is tracked. Include it in the same change whenever `project.yml` modifies the project structure or build settings.

## Test command

```sh
xcodebuild -project TailRemote.xcodeproj \
  -scheme TailRemote \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

If that simulator is unavailable, substitute an installed iPhone simulator from `xcrun simctl list devices available`.

## Code style

- Prefer native SwiftUI and UIKit APIs over additional dependencies.
- Keep authentication and networking failures explicit and user-actionable.
- Keep touch interactions predictable and test their coordinate math separately.
- Do not weaken macOS Screen Sharing authentication or suggest exposing port `5900` publicly.
