# OATS MIDI KEYMAP v0.9.0

Native macOS + iPadOS. One SwiftUI codebase, CoreMIDI engine.

Keystation 61es ──USB──▶ **OATS MIDI KEYMAP** ──▶ virtual MIDI source named `OATS MIDI KEYMAP`
                                        └──▶ optional hardware destination (the organ)

The virtual source means Logic / MainStage / anything just sees a MIDI device called
**OATS MIDI KEYMAP** in its input list. No IAC bus. No loopback driver. No routing hacks.

---

## Build — the 90-second path

Nothing here needs an Apple Developer account for macOS.

```bash
brew install xcodegen          # once
cd OatsKeymap
xcodegen generate
open OatsKeymap.xcodeproj
```

Then in Xcode: pick **My Mac**, hit **⌘R**.

### If you'd rather not install xcodegen

1. Xcode → **File ▸ New ▸ Project ▸ Multiplatform ▸ App**. Name it `OatsKeymap`.
2. Delete the generated `ContentView.swift` and `OatsKeymapApp.swift`.
3. Drag every file from `Sources/` into the project. Check *Copy items if needed*.
4. **Signing & Capabilities** → remove **App Sandbox** if it's there.
   CoreMIDI virtual endpoints and the sandbox are a fight you don't need for a local tool.
5. ⌘R.

### iPad
Same project, switch the run destination to your iPad. You need the Keystation on a
**powered** USB hub — the iPad won't reliably bus-power it. Free Apple ID = re-sign every
7 days. $99/yr = a year at a time.

### Expected warnings
`MIDISourceCreate`, `MIDIReceived`, `MIDISend` and `MIDIInputPortCreateWithBlock` are
soft-deprecated in favour of the UMP/MIDIEventList API. They compile and work on every
macOS and iOS you'll run this on. I used them deliberately — the UMP path has more places
to get bit-packing wrong, and a wrong byte here fires the wrong pipe.

---

## What it does

**Plot** — the keybed as a patch plot. Arm a channel (a gel), drag across the keys.

**Stacked assignments** — a key holds a *list* of outputs, not one. Each layer has its own
note, channel, velocity, label, mute. Three layers = three colour bands on the key face.
This is what makes registration possible: one key, several ranks.

**Ranks** — pull a stop and every plot key the rank actually has a pipe for gets a layer.
Keys outside the rank's compass get nothing, because the organ would do nothing.

**Board / pin** — every assignment shows which relay board and which pin it fires.
`Bd 214 · pin 33`. Export the hookup sheet and hand it to whoever's inside the case.

**Collisions** — two live layers on the same channel + note is a stuck note: the first
note-off kills both. Red bar on the key, listed in the sidebar. The engine also refuses
to double-fire an identical target.

**Held-note tracking** — release fires exactly what was pressed, even if you edit the map
mid-note. **Panic** kills everything and sends All Notes Off on all 16 channels.

---

## Gene's organ — confidence

| Rank | Bd | Ch | Notes | Pins | Rule | |
|---|---|---|---|---|---|---|
| Main Melody / Acc / Bass | 214 | 1 | 28–91 | 1–64 | `pin = note − 27` | ✅ verified column-by-column |
| Pan Flutes / Counter Mel | 331 | 2 | 48–69? | 1–22 | `pin = note − 47`? | ❌ **guessed. do not wire.** |
| Xylophone / Glockenspiel | 332 | 2 | 67–91 | 8–32 | `pin = note − 59` | ✅ verified |
| Trumpets | 329 | 3 | 55–86 | 1–32 | `pin = note − 54` | ✅ verified |
| Piccolos | 346 | 10 | 82–101 | 13–32 | `pin = note − 69` | ✅ verified |

Percussion (Bd 346, pins 1–12) is a **lookup, not an offset**. Only pins 1–3 are readable:
36 Bass Drum, 38 Snare 1, 40 Snare 2. The other nine are red in the app until you fill them.

**Registers are unsolved.** Bd 331 and Bd 332 both sit on channel 2 — MIDI can't choose
between them, the register does. The chart lists all twelve register *names* and none of
their note numbers. Type them into the Registers card and the FIRE buttons go live.

Everything above lives in `Organ.swift` as plain data. Nothing is hardcoded into the engine.
A flat daylight scan of that chart and this becomes five minutes of typing.

---

## v0.8.0 — on-site controller mapping

**Controller card (top of the sidebar)** — pick any MIDI device as *Ctl in*. It is a separate
input: nothing it sends is remapped or passed to the organ.

**LEARN** (header or Controller card) — everything mappable gets an amber outline. Tap a
target, then press / hit / move a control. Done. Targets: the 12 register pads, every rank's
PULL, the 16 out-channel gels, ARM, PANIC, pad-clear.

Triggers: note-on, program change, or any CC crossing 64 upward. Bindings and the chosen
controller are saved on this device (Mac or iPad), not in the instrument file, and the
controller is re-grabbed by name when it's plugged back in.

**Edit is the default tool** — press a key on the Keystation and the editor jumps to it.
Paint is still there for bulk work: arm a channel, drag across a run of keys.

**Icon** — `Sources/Assets.xcassets/AppIcon.appiconset` (macOS sizes + iPad 1024).
