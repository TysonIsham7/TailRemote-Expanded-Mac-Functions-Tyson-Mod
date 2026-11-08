# TailRemote features

Reference for anyone building a hands-on test checklist. It describes what this tree does today, based on the code in `TailRemote/` (mainly `RemoteDesktopView.swift`, `RemoteCanvasView.swift`, `RemoteKeyboardBridge.swift`, `VNCSession.swift`).

Screen terms used below:
- **Toolbar**: the bottom bar during a session: Keyboard, Trackpad, Spotlight, More (Paste, Prev, Next), Scroll, Keys, Hide. It scrolls sideways when it does not fit.
- **Keys row**: the strip of chips shown above the toolbar when Keys or Keyboard is on. The keyboard End key is labeled "End key" so it is not the disconnect control.
- **Status pill**: the capsule at the top showing the connection state. End sits beside it and disconnects.

---

## 1. Connection and sign-in

**What it does:** Connects to macOS Screen Sharing (VNC) over Tailscale using RoyalVNCKit, with Apple username + password auth.
**Where:** Connect screen (saved Mac list, add Mac form). During a session, the status pill at the top.
**Expected:** The status pill goes Connecting → Signing in → Loading desktop → Connected. The first frame shows as soon as it arrives. After that, the picture refreshes at up to 60 fps (30 preferred).
**Limits:** No relay and no account. Tailscale must be on for both devices. Screen Sharing can't list Mac accounts before sign-in. The connection is shared, so it doesn't kick a local user off.
**Verify:** Connect to a saved Mac and watch the pill reach CONNECTED. Use a wrong password: you should get a clear error and no crash. With Tailscale off: you should get an error, not an endless spinner.

## 2. Saved Macs, remembered username, Keychain password

**What it does:** Saves Mac entries (host, port, username) in UserDefaults. **Remember password** (on by default) saves the password in the iPhone Keychain for that host + port + username. The password is saved only after sign-in succeeds. It doesn't sync through iCloud and is available only while the phone is unlocked.
**Where:** The Connect screen's add/edit form and the Remember password toggle.
**Expected:** Reconnecting with Remember on doesn't ask for the password. Turning it off removes the saved password. If saving fails, a banner says "Connected, but the password couldn't be saved on this iPhone."
**Verify:** Connect with Remember on, End, reconnect: you shouldn't be asked for the password. Turn it off and reconnect: you should be asked. Kill the app and relaunch: saved Macs and usernames should still be there.

## 3. Import Tailscale Macs

**What it does:** Imports a JSON list of Mac names and addresses made on the Mac by `scripts/export-tailscale-macs.py`. No API key is needed and the file has no passwords.
**Where:** Connect screen, **Import Tailscale Macs**.
**Limits:** It's a one-time snapshot and doesn't refresh by itself.
**Verify:** Import the file. The list should fill, and no password field should be pre-filled.

## 4. Pointer and clicks (touchpad style)

**What it does:** The phone draws its own pointer, a white dot. Gestures:

| Gesture | Action |
| --- | --- |
| One-finger drag | Move the pointer (relative, like a trackpad) |
| Tap | Left click |
| Double-tap | Double-click |
| Two-finger tap | Right-click |
| Hold still for 0.45 s (moving less than 6 pt), then drag | Mouse-down drag (windows, sliders) |
| Double-tap, then start dragging within 0.55 s | Select (mouse held down during the drag) |

**Expected:** Each click shows a ring pulse at the clicked spot on the desktop, not where your finger is. The ring is blue for left clicks and green for right clicks, and pulses twice for a double-click. With Reduce Motion on, the pulse is a short fade with no growing ring. A slow swipe should move the pointer right away, not start a drag.
**Limits:** The first move centers the pointer on the Mac screen. Taps wait for the double-tap check, so a single tap has a small built-in delay.
**Verify:** Drag the pointer across the screen. Tap, double-tap and two-finger tap on Finder items. Hold-then-drag a window. Double-tap-then-drag across text to select it.

## 5. Two-finger scroll and one-finger Scroll mode

**What it does:**
- **Two-finger drag at 1×:** sends vertical scroll-wheel steps.
- **Scroll button** (toolbar): turns one-finger drag into scrolling, both vertical and horizontal, whichever direction is larger. A pill shows "ONE FINGER SCROLLS". The setting is remembered across launches.

**Expected:** Finger scroll sends one wheel detent per 4 points of travel, or per 2 points while Scroll mode is on, and keeps the unused fraction. A long swipe is not cut to 6 steps. Scroll mode leftovers reset when your finger lifts.
**Limits:** Two-finger scroll is vertical only. While zoomed in, two-finger drag pans instead of scrolling. A double-tap-select drag always moves the pointer, even in Scroll mode. Trackpad and mouse-wheel scrolling use 10-point steps with no per-event cap.
**Verify:** In Safari, slow two-finger drag, then a long fast one: watch whether fast swipes feel capped. Turn Scroll on: one-finger drag should scroll and sideways drag should scroll sideways. Turn Scroll off: one-finger drag should move the pointer again. Relaunch: Scroll mode should keep its last setting.

## 6. Pinch zoom, pan, edge-follow

**What it does:** Pinch zooms from 1× to 4×, and the point between your fingers stays fixed. Two-finger drag while zoomed pans the view. Moving the pointer near the edge while zoomed makes the view follow it. Pointer speed stays the same at every zoom level.
**Expected:** Releasing a pinch below 1.05× snaps back to 1× and centered. If the Mac's resolution changes, zoom resets.
**Verify:** Pinch to 4×, pan around, drag the pointer to an edge so the view follows, then pinch back to 1×. The picture should snap back to centered.

## 7. Screen fitting (centered, avoids keyboard and controls)

**What it does:** Fits the Mac picture to the screen and centers it in the open area. It shifts only when the on-screen keyboard or the full control bar covers the bottom. The small "Controls" button you get after hiding doesn't count.
**Verify:** Open the keyboard: the picture should move up only as much as needed. Hide the controls: the picture should re-center. Rotate the phone: it should refit and taps should still land where you tap.

## 8. Toolbar buttons

| Button | Sends / does |
| --- | --- |
| Keyboard | Shows/hides the phone keyboard (also opens the Keys row) |
| Prev (under More) | Control-Left arrow (previous desktop space) |
| Next (under More) | Control-Right arrow (next desktop space) |
| Scroll | Turns one-finger Scroll mode on/off |
| Keys | Shows/hides the Keys row |
| Hide | Hides the toolbar; a "Controls" button (bottom-right) brings it back. Remembered across launches |
| End | Top bar, beside the status pill. Closes the keyboard and disconnects. It is not in the scrolling toolbar, where it was clipped off the phone |

**Verify:** Prev/Next should move one Space. Hide → Controls should bring back the toolbar. End should return you to the Connect screen and the Mac's Screen Sharing session should end.

## 9. Keys row (modifiers and shortcuts)

**What it does:**
- **Modifier chips ⌘ ⌥ ⌃ ⇧:** tap to latch one (it turns blue). Latched modifiers are held for the **next** key, then all clear. That key can come from the chip row, the phone keyboard, Backspace or Return.
- **Shortcut chips:** ⌘C, ⌘V, ⌘Z, ⌘A, ⌘X, ⌃C.
- **Keys:** Esc, Tab, Right (right-click at the pointer), Desks (Control-Up = Mission Control), arrow keys, Home, End, PgUp, PgDn, ⌫.

**Expected:** A latched modifier plus a typed letter sends one shortcut, then later letters type plain. Tapping a latched chip again unlatches it.
**Verify:** Latch ⌘ and type a space: Spotlight should open (this is how to do Command-Space on `main`). Use ⌘A, ⌘C, then ⌘V in another field. Latch ⇧ and type a letter: you should get one capital, then lowercase again. Desks should open Mission Control.

## 10. Phone keyboard typing

**What it does:** A hidden text field passes phone keystrokes to the Mac. Auto-capitalization, autocorrect, smart quotes/dashes and inline predictions are all off, so the text arrives as typed in lowercase. A hidden placeholder character keeps iOS from turning Shift back on. Return sends Return. Each Backspace sends one Delete, and repeats within 40 ms are dropped so one tap is one delete.
**Limits:** Characters are sent one key at a time, so very long input is typed out key by key.
**Verify:** Type a sentence: it should be all lowercase unless shifted. Tap Backspace 5 times: exactly 5 characters should be deleted. Hold Backspace and check it doesn't over-delete. Return should make a new line or submit.

## 11. Clipboard

**What it does:** Clipboard redirection is on, so text can move both ways during a session. Paste, under More, types the iPhone pasteboard into the focused Mac field one character at a time. A newline is sent as Return. The client does not send the VNC clipboard message ahead of Command-V.
**Verify:** Copy on the iPhone, focus a Mac text field, and tap Paste. Copy on the Mac and check the iPhone pasteboard. ⌘V on the Keys row is a separate shortcut.

## 12. Disconnect and reconnect

**What it does:** End disconnects and does not reconnect. While a session is on screen, leaving the app keeps the socket for iOS's short background window. When that window ends, or the Mac drops the connection, opening the app again reconnects with the Keychain password if Remember password is on.
**Limits:** There is no continuous background mode. If the phone is locked, the Keychain read can fail; the connect form then shows that error and an empty password. With Remember password off, reconnect by hand.
**Verify:** With Remember on, background the app until iOS suspends it, then open it and confirm it signs in again. Tap End and confirm it stays on the connect screen. Lock the phone, End the session, and confirm a failed unlock is visible instead of a blank form with no error.

## 13. Known limits (from README)

No Mac-to-iPhone audio, no file transfer, no Face ID for remote Passkeys, iOS 17+. iPhone and iPad are both targeted. See section 14 for iPad.

## 14. iPad window, pointer, and hardware keyboard

**What it does:** The app targets iPhone and iPad. iPad allows every orientation and does not require full screen, so Split View, Slide Over, and Stage Manager can resize the window. The remote picture aspect-fits that window. Pinch zoom and two-finger pan are unchanged. End is in the top bar, beside the status pill, on both sizes. Spotlight (Command-Space) is in the session toolbar on both iPhone and iPad. Prev and Next are under More, with Paste. A regular-size iPad window uses a wider toolbar and wraps the key chips when they fit.

**Pointer:** With a trackpad or mouse, the cursor follows the pointer on the picture (including while zoomed). Primary click and double-click are left clicks. Secondary click is a right-click. A primary drag holds the button down. Apple Pencil taps and double-taps click at that point. Finger gestures stay relative, as on iPhone.

**Scroll:** Finger scrolling sends one wheel detent per 4 points of travel (2 points in Scroll mode) and keeps the unused fraction for the next sample, so a long swipe is not cut to 6 steps. Wheel steps are batched before they are sent. Two-finger drag scrolls the Mac at 1× and pans the picture while zoomed. Trackpad and mouse-wheel scrolling use 10-point steps without a per-event cap.

**Hardware keyboard:** When a Magic Keyboard or other external keyboard is connected, key-down and key-up go to the Mac, including Command, Option, Control, Shift, arrows, Escape, and function keys. Modifiers stay down until released. Command-Space, Command-Tab, and Escape ask to take priority over the iPad system action. The on-screen Keyboard button still opens the touch keyboard when no hardware keyboard is attached.

**Security:** Still a Tailscale Screen Sharing client only. No new listener. The bundle ID comes from gitignored `Config/Local.xcconfig`; the tracked default is a placeholder.

**Verify on a device:** Resize in Stage Manager and Split View. Pinch, pan, and finger-drag on the picture. Move, click, right-click, and scroll with a trackpad. Tap with Apple Pencil. Type, hold Shift, and use Command-C and Command-Space from a hardware keyboard. On iPhone, tap End in the top bar and Spotlight in the toolbar. Confirm the rest of the iPhone layout still matches section 8.

---

## Not in this tree

Finger scroll, the trackpad panel, Paste, Spotlight, and background reconnect are in this tree. See sections 5, 8, 11, 12, and 14. There is no separate Logout control. End is the disconnect.
