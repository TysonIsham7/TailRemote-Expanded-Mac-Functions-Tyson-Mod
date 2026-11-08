# TailRemote features

Reference for anyone building a hands-on test checklist. It describes what `main` does today, based on the code in `TailRemote/` (mainly `RemoteDesktopView.swift`, `RemoteCanvasView.swift`, `RemoteKeyboardBridge.swift`, `VNCSession.swift`). Anything not in `main` is listed under **Unconfirmed / local-only** at the end.

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

**Expected:** You need at least 10 pt of finger travel to send scroll steps. Each event sends 1 step per 10 pt, **capped at 6 steps** (see Unconfirmed). Scroll mode leftovers reset when your finger lifts.
**Limits:** Two-finger scroll is vertical only. While zoomed in, two-finger drag pans instead of scrolling. A double-tap-select drag always moves the pointer, even in Scroll mode.
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

**What it does:** RoyalVNCKit clipboard redirection is turned **on** in the connection settings (`isClipboardRedirectionEnabled: true`). `main` has no explicit Paste button.
**Verify:** Copy text on the iPhone, then use ⌘V from the Keys row in a Mac text field and see if it arrives. Also copy on the Mac and check the iPhone clipboard. Record the result either way: whether it works isn't confirmed.

## 12. Disconnect and reconnect

**What it does:** End disconnects cleanly. When the connection drops, the app clears the session and forgets the in-memory password. A remembered password stays in the Keychain.
**Limits:** `main` has **no automatic reconnect**. After backgrounding, a phone lock, a network change or the Mac sleeping, expect to see Disconnected and reconnect by hand.
**Verify:** Background the app for 30 s, lock the phone for 2 min, switch Wi-Fi to cellular, and sleep the Mac. For each, note what the app shows and whether reconnecting by hand works.

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

## Unconfirmed / local-only (pending until pushed)

These items come from the task "TailRemote: test feedback batch 1 on iPhone" and recent notes. They are on a local branch (`feedback-batch-1`) and are **not in `main`** as of this commit. Treat them as pending until they're pushed, then move them into the sections above.

| Item | Status on `main` |
| --- | --- |
| Scroll fix (batch 1) | Pending. `main` still caps each scroll event at 6 steps (two-finger and one-finger) |
| Fix for the 6-step cap on long swipes | Pending. The cap is still in `RemoteCanvasView.swift` |
| Trackpad changes (batch 1) | Pending. `main` has the gestures in section 4 only |
| Trackpad mode panel | Not in `main` |
| Spotlight (Command-Space) toolbar button | In the session toolbar on iPhone and iPad |
| Logout (batch 1) | Pending. `main` has only End (disconnect) |
| Passwords (batch 1) | Pending. `main` behavior is described in section 2 |
| Reconnect (batch 1) | Pending. `main` has no automatic reconnect |
| Paste (batch 1) | Pending. `main` has clipboard redirection on but no Paste button |
