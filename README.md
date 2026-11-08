<p align="center">
  <img src="Assets/Brand/tailremote-logo.png" width="112" alt="TailRemote logo">
</p>

<h1 align="center">TailRemote</h1>

<p align="center">
  A fork of <a href="https://github.com/C4T4/TailRemote">C4T4/TailRemote</a> by Catalin Waack — a direct, private iPhone and iPad remote for your Mac.
</p>

This repository is a GitHub fork of [C4T4/TailRemote](https://github.com/C4T4/TailRemote) by Catalin Waack. His app is the whole foundation: a direct, private iPhone client that controls a Mac through macOS Screen Sharing, with no relay and no account. It is MIT licensed, and the copyright in [LICENSE](LICENSE) stays his. This fork does not replace his project. It keeps that work and adds phone and iPad controls for use away from the Mac.

## Who this is for

This is for anybody who wants to be able to do things on their Mac while they are remote and away from it.

You stay on your iPhone or iPad. The Mac stays where it is. Tailscale carries the connection, and Screen Sharing is what you sign in to.

## What Catalin's app already does

- Apple Screen Sharing authentication through RoyalVNCKit
- A live picture of the Mac, with a pointer drawn on the phone
- Touchpad-style movement, clicks, dragging, and two-finger scrolling
- Click pulses, including double-clicks and right-clicks
- Pinch zoom from 1× to 4×, with panning and cursor edge-following
- A saved Mac list, a username remembered per Mac, and passwords in the iPhone Keychain
- A way to import Mac names from Tailscale on your Mac, without an API key

## What this fork adds

- Desktop space switching: **Prev** and **Next** send Control-Left and Control-Right, and **Desks** sends Control-Up
- One-finger scroll, turned on with the **Scroll** button
- Modifier keys: Command, Option, Control, and Shift stay down until the next key
- Lowercase typing, so the phone keyboard does not force a capital letter
- A backspace fix, so one delete on the phone is one delete on the Mac
- Centered screen fitting, so the Mac picture sits in the open part of the phone and moves only when the keyboard or the full control bar covers the bottom
- A **Keys** row for shortcuts, arrows, Esc, Tab, and a right-click
- A **Hide** button that tucks the controls away
- Double-tap-drag select: double-tap, then drag within about half a second, to select
- Trackpad mode on the phone, with a **More** menu that can type the device clipboard into the focused Mac field
- Background reconnect with a saved password after a short background window
- iPad windows (including Split View, Slide Over, and Stage Manager), pointer and trackpad input, hardware keyboard forwarding, and Apple Pencil taps
- Feature checklist for testers in [docs/FEATURES.md](docs/FEATURES.md)

## Prerequisites

You need:

- a Mac with Apple silicon
- an iPhone or iPad with iOS 17 or iPadOS 17+
- the latest OS on both
- [Tailscale](https://tailscale.com/download) on both, connected to the same tailnet
- an Xcode build signed with your own team
- Developer Mode turned on for the device you install to
- approval for the Tailscale VPN (and the local-network prompt, if iOS asks)

On the Mac, turn on **System Settings → General → Sharing → Screen Sharing**.

`com.example.tailremote` is a placeholder bundle ID. Put your own team and bundle ID in `Config/Local.xcconfig`, which git ignores. Copy [`Config/Local.xcconfig.example`](Config/Local.xcconfig.example) and set `DEVELOPMENT_TEAM` and `TAILREMOTE_BUNDLE_IDENTIFIER` there. Leave both out of `project.yml`, the Xcode project, and this README. Choosing a team in Signing & Capabilities writes the team into the project file, so prefer the local file. Run `scripts/install-git-hooks.sh` once in your clone. The commit and push checks then refuse your local values, a filled-in Apple team ID, a provisioning profile, or a certificate. Do not set a global `PRODUCT_BUNDLE_IDENTIFIER` override, because Xcode also applies that override to embedded frameworks and iOS then rejects the duplicate IDs.

## Setup

```sh
git clone <this-repo-url>
cd <repo-directory>
open TailRemote.xcodeproj
```

Select your iPhone and press Run. The shared scheme uses **Release** for Run so Screen Sharing authentication and screen decoding stay fast. Tests use **Debug**.

Add your Mac with its Tailscale address and the macOS username from `whoami`. **Remember password** is on by default and stores that password in the device Keychain for that Mac, port, and username. It stays on that device, does not sync through iCloud, and is removed if you turn the toggle off.

To fill the Mac list from the Mac itself, with Tailscale connected:

```sh
python3 scripts/export-tailscale-macs.py ~/Downloads/TailscaleMacs.json
```

Move that file to the iPhone or iPad and use **Import Tailscale Macs**. It holds names and addresses, not passwords. Keep the file out of the repository.

Paste this repo link into any AI assistant like ChatGPT and it will walk you through setup one step at a time. More advanced agents can do much of the setup for you.

## Devices

The deployment target and family below come from the project settings:

- The iOS deployment target is 17.0. `UITextField.inlinePredictionType`, which the lowercase keyboard uses, requires iOS 17 and is called with no availability check. iOS 16 and earlier cannot build this tree as it stands.
- The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY` 1,2). Mac Catalyst is off. iPad supports the usual window sizes, including Split View, Slide Over, and Stage Manager.
- There is no macOS deployment target. The Mac is the Screen Sharing computer, not a built app.

If your devices aren't compatible, fork this repo and adapt it for them. An older iPhone or a Mac this tree has not been tried on is a real next step, not a dead end.

## Controls

| Gesture or button | Action |
| --- | --- |
| One-finger drag | Move the pointer |
| **Scroll**, then one-finger drag | Scroll the Mac |
| Tap / double-tap | Click / double-click |
| Double-tap, then drag | Select, while the drag starts within about half a second |
| Hold still for about half a second, then drag | Drag a window, slider, or item |
| Two-finger tap | Right-click |
| Two-finger drag at 1× | Scroll the Mac |
| Pinch | Zoom from 1× to 4× |
| Two-finger drag while zoomed | Pan around the desktop |
| **Prev** / **Next** | Previous or next desktop, under **More** |
| **Desks** | Mission Control |
| **Trackpad** | On-screen trackpad panel (phone layout) |
| **More** | Paste clipboard text, Prev, and Next |
| **Keys** | Command, Option, Control, Shift, and the shortcut row |
| **Spotlight** | Command-Space on iPhone and iPad, then opens the keyboard |
| **Hide** | Hide the controls |
| **End** | Top bar, beside the status pill. Disconnects |
| Pointer / mouse (iPad) | Move the cursor directly; secondary click is right-click |
| Trackpad scroll (iPad) | Wheel steps without the finger-swipe step cap |
| Apple Pencil | Tap to click |
| Hardware keyboard (iPad) | Forwards keys and modifiers to the Mac |

While zoomed, moving the pointer near an edge follows it across the desktop. Pointer sensitivity stays the same at every zoom level.

## Limitations

- There is no Mac-to-iPhone audio routing.
- Remote Passkeys will not trigger Face ID on the phone. Approve those on the Mac, or with whatever that Mac already uses.
- Tailscale imports are a saved snapshot. They do not refresh by themselves.
- Screen Sharing does not list Mac accounts before you sign in.
- There is no file transfer.

## Security model

Tailscale gets you to the Mac. It does not replace Screen Sharing's own sign-in. The password goes only to the Mac you selected, and only for that handshake. The host and username are kept in `UserDefaults`. A remembered password is a Keychain item available only while this device is unlocked.

Only connect to Macs and networks you trust. Do not publish port 5900 on the public internet. See [SECURITY.md](SECURITY.md) for reporting vulnerabilities and the supported threat model. Distribution notes for the upstream App Store / TestFlight build live in [TESTFLIGHT.md](TESTFLIGHT.md) and [PRIVACY.md](PRIVACY.md).

## Development

The generated Xcode project is committed so contributors can build immediately. [`project.yml`](project.yml) is its source of truth. See [CONTRIBUTING.md](CONTRIBUTING.md).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project TailRemote.xcodeproj   -scheme TailRemote   -destination 'platform=iOS Simulator,name=iPhone 16 Pro'   test
```

For iPad-oriented unit tests, substitute an installed iPad simulator from `xcrun simctl list devices available`.

## License

TailRemote is available under the [MIT License](LICENSE).

Copyright (c) 2026 Catalin Waack.

Tailscale and Apple product names are trademarks of their respective owners.
