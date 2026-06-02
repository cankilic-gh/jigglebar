# JiggleBar ☕

A tiny macOS **menu-bar anti-idle tool**. When it's on, it periodically nudges the
mouse by a pixel or two (then puts it right back) and/or taps the inert **F15**
key, so the system never registers you as idle. Apps like Slack, Teams, and Google
Chat stay showing **active** instead of flipping you to *away/offline* after a few
minutes of inactivity.

No Electron, no dependencies — a single native Swift/AppKit binary. It lives only
in the menu bar (no Dock icon).

---

## Features

- **One-click On/Off** from the menu bar (☕ icon).
- **Methods:** mouse nudge, inert F15 key press, or both (default).
- **Interval:** 30 s · 60 s · 2 min · 5 min (default 2 min).
- **Randomized timing** (±50%) so the cadence isn't perfectly periodic.
- **Optional display-sleep prevention** via an IOKit power assertion.
- **Launch at login** (modern `SMAppService`).
- Remembers your settings and resumes its last on/off state on next launch.
- Invisible cursor movement — it always returns the pointer to its exact spot.
- F15 has no action in virtually any app, so it never disturbs what you're doing.

---

## Build & install

Requires macOS 13+ and the Swift toolchain (comes with Xcode or the Command Line
Tools: `xcode-select --install`).

```bash
git clone https://github.com/cankilic-gh/jigglebar.git
cd jigglebar
./build.sh                          # produces build/JiggleBar.app
cp -R build/JiggleBar.app /Applications/   # optional but recommended
open /Applications/JiggleBar.app
```

A ☕ icon appears in the menu bar. Click it → **Başlat / Start**.

> Installing on another Mac is the same three steps: clone, `./build.sh`, copy to
> `/Applications`. Nothing else to configure.

---

## Accessibility permission (required)

To post synthetic mouse/keyboard events, macOS requires Accessibility access. On
first start you'll be prompted automatically. If not, enable it manually:

**System Settings → Privacy & Security → Accessibility → enable JiggleBar.**

The app is ad-hoc code-signed by `build.sh` so the permission sticks across
launches.

---

## Menu options

| Option | What it does |
|---|---|
| **Start / Stop** | Toggle the anti-idle loop. |
| **Method** | Mouse + Keyboard (F15) · Mouse only · Keyboard only. |
| **Interval** | How often it triggers (30 s – 5 min). |
| **Randomize timing (±50%)** | Jitters each interval so it's not perfectly regular. |
| **Prevent display sleep too** | Holds an IOKit assertion to keep the screen awake. |
| **Launch at login** | Registers/unregisters via `SMAppService`. |

---

## How it works

- A repeating timer fires every `interval` (optionally jittered ±50%).
- On each tick it posts events through `CGEventSource(.hidSystemState)`, which
  resets the system's HID idle timer — the same signal presence-aware apps read.
- The mouse nudge moves the cursor a couple of pixels and immediately moves it
  back to the original coordinate, so you never see it twitch.
- The keyboard tap sends F15 (key code 113) down+up, which no app maps to an
  action by default.
- "Prevent display sleep" uses `IOPMAssertionCreateWithName` with
  `kIOPMAssertionTypePreventUserIdleDisplaySleep`.

---

## Project layout

```
jigglebar/
├── Sources/main.swift   # the entire app (AppKit menu-bar controller)
├── build.sh             # compiles with swiftc, bundles .app, ad-hoc signs
├── README.md
└── LICENSE
```

---

## Troubleshooting

**Still showing as "away" / "offline"?** The app may be working fine — the cause is
usually one of these:

- **Interval too long.** With a long interval plus randomized timing, the gap
  between nudges can exceed your chat app's away threshold (Teams is often ~5 min,
  Slack ~10 min). Use **60 s** for a comfortable margin.
- **The Mac went to sleep.** If the display/system sleeps, no timer fires and you
  go away. Enable **Prevent display sleep too** in the menu.
- **Closing the lid always sleeps the Mac.** This is a hardware behavior no
  software jiggler can override. Leave the lid open when you step away (or use a
  clamshell setup with external power + display).
- **Stale Accessibility trust after a rebuild.** Each `./build.sh` ad-hoc-signs the
  app with a new code signature. macOS may still list JiggleBar as enabled but
  silently drop its events because the binary changed. Fix: toggle JiggleBar off
  and back on in **System Settings → Privacy & Security → Accessibility** (or
  remove and re-add it). Best practice: build once, copy to `/Applications`, grant
  permission there, and don't rebuild over it.

**How to verify it's actually working.** Stop touching the mouse/keyboard and watch
the system idle timer — it should reset to ~0 on every interval:

```bash
# Sample the HID idle time (seconds) for 45s without touching input.
for i in $(seq 0 15); do
  ioreg -c IOHIDSystem | awk -F'= ' '/HIDIdleTime/ {printf "idle=%.1fs\n",$2/1e9; exit}'
  sleep 3
done
```

You can also confirm macOS accepts the synthetic events as real activity:

```bash
pmset -g assertions | grep -i jigglebar   # shows the active assertion/tickle
```

A healthy run looks like a sawtooth: the idle time climbs toward your interval,
then drops back to ~0 on every nudge, and **never grows unbounded**. Example from a
~14-minute hands-off run at a 60 s interval — idle never exceeded ~37 s and the
Slack presence dot stayed green the whole time, well past the 10-minute away
threshold:

```
07:56:17  idle=36.0s
07:56:48  idle=6.0s     <- nudge reset it
07:57:18  idle=36.1s
07:57:48  idle=6.1s     <- nudge reset it
...                      (max idle over 27 samples = 37.2s)
```

If instead the idle time keeps climbing past your interval, the events are being
dropped — re-check the stale-trust fix above.

---

## License

MIT — see [LICENSE](LICENSE).
