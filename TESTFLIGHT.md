# Distribution notes

This tree is not the upstream TestFlight app. It does not contain an Apple team. The committed Xcode project uses the placeholder bundle ID `com.example.tailremote`. A person building it chooses their own Apple team and their own bundle ID, in the gitignored local config, and does not reuse the upstream bundle ID.

## Upstream app

These notes keep the upstream attribution. The original TailRemote app was prepared by Waack International LLC.

- Upstream bundle ID: `com.waack.TailRemote`
- Upstream version described here: `1.0.0` (build `1`)
- Upstream team: Waack International LLC

None of those identifiers are configured in this tree. `project.yml` keeps the `com.example.tailremote` placeholder. Switching this repo from that placeholder to `com.waack.*` is not done, and it is not the right bundle ID for this fork.

## Already true of this tree

- Placeholder bundle IDs under `com.example.tailremote`
- Marketing version `1.0.0` and build `1`
- Export compliance Info.plist key set to non-exempt encryption = NO (standard exempt networking / Screen Sharing). Confirm the App Store Connect questionnaire matches whatever build you actually submit.
- Local network usage string present
- Single 1024×1024 App Store icon in the asset catalog
- Privacy policy draft in [`PRIVACY.md`](PRIVACY.md)

## If you distribute your own build

### 1. Apple Developer

1. Sign in with the Apple team you control.
2. Register a new bundle ID that you own. Do not register `com.waack.TailRemote` for this fork.
3. Enable only capabilities you actually use.

### 2. App Store Connect

1. Create the iOS app with the bundle ID you registered.
2. Choose your own SKU.
3. Host [`PRIVACY.md`](PRIVACY.md) at a public HTTPS URL you control and paste that URL into App Privacy.
4. App Privacy answers for the current code:
   - No data collected by the developer from the app for tracking or analytics
   - Credentials and the on-device Mac list stay on the device. This fork does not upload that list to Waack International LLC or to any other service of its own.
5. Prepare the screenshots your submission requires.
6. Review notes for Apple: Tailscale plus Screen Sharing, no demo account, and a Mac the reviewer can reach with Screen Sharing enabled.

### 3. Xcode

1. Open `TailRemote.xcodeproj`.
2. Select your own team. This project does not name one.
3. Set the bundle identifier to the ID you registered, not `com.waack.TailRemote` and not a personal ID committed in git.
4. Archive and upload with your own account.

The upstream privacy page remains at `https://c4t4.github.io/TailRemote/privacy/`. That page describes the upstream app. This tree's policy text is [`PRIVACY.md`](PRIVACY.md).

## Regenerating the Xcode project

After editing `project.yml`:

```sh
cd /path/to/TailRemote
xcodegen generate
```

Commit both `project.yml` and the updated `TailRemote.xcodeproj` only after they still use a placeholder or your own unshared local config. Do not commit a personal team or bundle ID.
