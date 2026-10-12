# Security policy

## Supported versions

TailRemote is an early-stage project. Security fixes are made on the latest `main` branch only.

## Reporting a vulnerability

Do not publish exploit details, passwords, private keys, authentication tokens, network addresses, or tailnet names.

This fork does not run a vulnerability inbox, and it does not pass reports on to the original project. Keep the details off public pages.

## Threat model

TailRemote assumes:

- The iPhone and Mac are trusted devices.
- Tailscale or another trusted network limits who can reach Screen Sharing.
- macOS Screen Sharing authentication remains enabled.
- The Mac account password is not reused or shared with untrusted people.

TailRemote does not make an exposed VNC server safe. Do not forward TCP port `5900` from the public internet.

## Credential handling

The host, username, and Remember password preference are stored in iOS `UserDefaults`.
When Remember password is enabled, the password is saved only after successful
authentication, using a generic password item in the app's Keychain. Each item is
scoped to the normalized hostname, port, and username. Changing the selected Mac
or account clears the form password before loading a matching saved item.

Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and disable synchronization.
They are accessible only while the iPhone is unlocked, do not sync to iCloud, and
do not migrate to another device. Turning Remember password off removes the item
for the selected Mac/account. Failed sign-ins do not overwrite a saved password.

Passwords are never stored in `UserDefaults`, logs, analytics, or the repository.
The active session's in-memory password is cleared on disconnect. Keychain errors
are shown without including the password, account, or host in diagnostics.
