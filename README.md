<p align="center">
  <img src="Assets/Brand/tailremote-logo.png" width="112" alt="TailRemote logo">
</p>

<h1 align="center">TailRemote</h1>

<p align="center">
  A fork of <a href="https://github.com/C4T4/TailRemote">C4T4/TailRemote</a> by Catalin Waack.
</p>

This repository is a GitHub fork of [C4T4/TailRemote](https://github.com/C4T4/TailRemote) by Catalin Waack. His app is the whole foundation: a direct, private iPhone client that controls a Mac through macOS Screen Sharing, with no relay and no account. It is MIT licensed, and the copyright in [LICENSE](LICENSE) stays his. I am new to open source. This fork does not replace his project. It keeps that work and adds the phone controls I wanted while I was away from my Mac.

## Who this is for

This is for anybody who wants to be able to do things on their Mac while they are remote and away from it.

You stay on your iPhone. The Mac stays where it is. Tailscale carries the connection, and Screen Sharing is what you sign in to.

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

## Prerequisites

You need:

- a Mac with Apple silicon
- an iPhone
- the latest OS on both
- [Tailscale](https://tailscale.com/download) on both, connected to the same tailnet
- an Xcode build signed with your own team
- Developer Mode turned on for the iPhone
- approval for the Tailscale VPN (and the local-network prompt, if iOS asks)

On the Mac, turn on **System Settings → General → Sharing → Screen Sharing**.

`com.example.tailremote` is a placeholder bundle ID, not an ID you should ship. Before you install, change `TAILREMOTE_BUNDLE_IDENTIFIER` in [`project.yml`](project.yml) to an ID you control, then run `xcodegen generate` (or set the same ID in Signing & Capabilities). Choose your own team there. No Apple development team is stored in this project. Do not set a global `PRODUCT_BUNDLE_IDENTIFIER` override, because Xcode also applies that override to embedded frameworks and iOS then rejects the duplicate IDs.

## Setup

```sh
git clone https://github.com/TysonIsham7/TailRemote-Expanded-Mac-Functions-Tyson-Mod.git
open TailRemote-Expanded-Mac-Functions-Tyson-Mod/TailRemote.xcodeproj
```

Select your iPhone and press Run. The shared scheme uses **Release** for Run so Screen Sharing authentication and screen decoding stay fast. Tests use **Debug**.

Add your Mac with its Tailscale address and the macOS username from `whoami`. **Remember password** is on by default and stores that password in the iPhone Keychain for that Mac, port, and username. It stays on that phone, does not sync through iCloud, and is removed if you turn the toggle off.

To fill the Mac list from the Mac itself, with Tailscale connected:

```sh
python3 scripts/export-tailscale-macs.py ~/Downloads/TailscaleMacs.json
```

Move that file to the iPhone and use **Import Tailscale Macs**. It holds names and addresses, not passwords. Keep the file out of the repository.

Paste this repo link into any AI assistant like ChatGPT and it will walk you through setup one step at a time. More advanced agents can do much of the setup for you.

## Devices

I have tested it only on Apple Silicon Macs and iPhone 16 or newer, on the latest developer betas. I can't personally test other devices. Everything else below is untested.

As of 12 October 2026, the current developer betas are iOS 27.2 beta 3 (build 24B5099f, 5 October 2026), macOS 27.2 beta 3 (5 October 2026), and Xcode 27.2 beta 2, which asks for macOS Tahoe 26.6 or later. That Xcode still debugs on-device builds for iOS 17 and later, and it still accepts the Swift 5 language mode this project sets. Those are the only devices I have tried.

The numbers below come from the project, not from extra devices:

- The iOS deployment target is 17.0. `UITextField.inlinePredictionType`, which the lowercase keyboard uses, requires iOS 17 and is called with no availability check. iOS 16 and earlier cannot build this tree as it stands.
- The app target is iPhone only (`TARGETED_DEVICE_FAMILY` 1). Mac Catalyst is off. iPad is not a destination of this target.
- There is no macOS deployment target. The Mac is the Screen Sharing computer, not a built app. macOS 27 Golden Gate lists Apple silicon Macs from 2020 on.
- iPhone 16 models shipped with iOS 18, so they cannot go back to iOS 17. Only the current developer beta was tested on them.
- iPhone XS, iPhone XS Max, iPhone XR, and later phones can run iOS 17. They fall inside the deployment target. They are untested.
- Older Macs, Intel Macs, iPads, and phones that stop at iOS 16 are outside what this tree is set up to build or what I have tried.

If your devices aren't compatible, fork this repo and have your own agents make it work for your devices. An iPad layout, an older iPhone, or a Mac I have not used is a real next step, not a dead end. Treat each incompatible device as a contribution waiting for its own fork.

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
| **Prev** / **Next** | Previous or next desktop |
| **Desks** | Mission Control |
| **Keys** | Command, Option, Control, Shift, and the shortcut row |
| **Hide** | Hide the controls |

While zoomed, moving the pointer near an edge follows it across the desktop. Pointer sensitivity stays the same at every zoom level.

## Limitations

- There is no Mac-to-iPhone audio routing.
- Remote Passkeys will not trigger Face ID on the phone. Approve those on the Mac, or with whatever that Mac already uses.
- Tailscale imports are a saved snapshot. They do not refresh by themselves.
- Screen Sharing does not list Mac accounts before you sign in.
- There is no file transfer.

## Security model

Tailscale gets you to the Mac. It does not replace Screen Sharing's own sign-in. The password goes only to the Mac you selected, and only for that handshake. The host and username are kept in `UserDefaults`. A remembered password is a Keychain item available only while this iPhone is unlocked.

Only connect to Macs and networks you trust. Do not publish port 5900 on the public internet. See [SECURITY.md](SECURITY.md) for the threat model.

## License

TailRemote is available under the [MIT License](LICENSE).

Copyright (c) 2026 Catalin Waack.

Tailscale and Apple product names are trademarks of their respective owners.
