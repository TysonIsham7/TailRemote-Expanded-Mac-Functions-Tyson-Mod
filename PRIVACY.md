# Privacy Policy for TailRemote

**Effective date:** 8 November 2026

**Upstream app:** TailRemote by Waack International LLC (`com.waack.TailRemote`). That name and bundle ID identify the original app. They are not the signing identity of this tree.

**This tree:** a separate fork. The committed project uses the placeholder bundle ID `com.example.tailremote` and does not select an Apple team. It is not the upstream TestFlight app. This fork does not publish a contact address.

## Summary

TailRemote is a private iPhone remote for your Mac. It connects over your Tailscale network to macOS Screen Sharing. There is no TailRemote account, no TailRemote cloud backend, and no analytics or advertising SDK in the app.

## Data TailRemote handles on your device

| Data | Where it lives | Purpose |
| --- | --- | --- |
| Mac display name, Tailscale address/hostname, port, username | On-device (`UserDefaults`) | Remember Macs you added or imported |
| Screen Sharing password (optional) | On-device Keychain when **Remember password** is on | Sign in again without retyping |
| Live screen pixels and input events | In memory during an active session only | Show and control the remote Mac |
| Clipboard text | iPhone pasteboard and the remote Mac, while clipboard redirection is on | Copy text between the two devices you connected |

Passwords are never written to `UserDefaults`, logs, or the repository. Keychain items stay on that iPhone, do not sync to iCloud, and are not available while the device is locked. Turning **Remember password** off deletes the saved password for that Mac and username. Disconnect clears the in-memory session password.

Clipboard redirection is on in this tree. Text from the Mac can be written to the iPhone pasteboard, and text on the iPhone pasteboard can be sent to the Mac. That is inherited client behavior. It is not limited to the in-memory screen image.

## What TailRemote does not collect

TailRemote does not:

- create user accounts or require an email login for the app itself
- operate a relay, hosted desktop service, or TailRemote server that receives your screen
- include analytics, crash reporters, advertising, or tracking SDKs
- sell personal data or share it with data brokers

## Network destinations

When you connect, TailRemote talks only to the Mac you select (Screen Sharing over your private Tailscale network). Credentials are sent to that Mac during the Screen Sharing authentication handshake.

Importing Macs from Tailscale uses a JSON file you export locally on your Mac. That file is not uploaded to Waack International LLC, and this fork has no service of its own that receives it.

Tailscale itself is a separate product from Tailscale Inc. Its privacy practices are governed by Tailscale, not by this policy.

## Third-party components

TailRemote embeds RoyalVNCKit for Screen Sharing / VNC client functionality. See the app's third-party notices for licenses. Those components run on your device as part of the connection you start. The accepted connection limits are described in [`SECURITY.md`](SECURITY.md).

## Children

TailRemote is not directed at children under 13.

## Your choices

- Do not enable **Remember password** if you do not want credentials stored on the iPhone.
- Delete saved Macs and passwords from within the app, or delete the app to remove on-device data.
- Only connect to Macs and networks you trust. Clipboard redirection copies text both ways during a session.

## Changes

This policy describes this fork's tree. The effective date at the top changes when the data practices change. The upstream app's policy is a separate document from Waack International LLC.

## Contact

This fork does not publish a contact address.
