# findphone

Locate a nearby Bluetooth device by signal strength, from the command line.

Built for the case where Find My is unavailable — for example when a device is
enrolled in MDM that disables it — but the device is still within Bluetooth
range and you just need to know which corner of the room it is in.

## Install

Grab the universal binary from [Releases](https://github.com/ben-z/findphone/releases):

```sh
tar -xzf findphone-macos-universal.tar.gz
xattr -dr com.apple.quarantine findphone
./findphone --help
```

It is unsigned, so macOS quarantines it on download; the `xattr` line clears
that. Requires macOS 13 or later.

## Build

```sh
swift build -c release
cp .build/release/findphone ~/bin/findphone
```

Requires the Swift toolchain from Xcode Command Line Tools. No dependencies.
For a universal arm64 + x86_64 binary, which is what CI ships:

```sh
./scripts/build-universal.sh dist
```

## Use

```sh
findphone            # survey mode: every nearby Apple handheld, by signal
findphone iphone     # hunt mode: track one device by name (case-insensitive)
findphone --list     # paired devices and their addresses
findphone --select   # choose one device from nearby list, then track it
```

Add `--sound` in hunt mode for clicks that speed up as you close in, the way a
parking sensor does — about one a second across a room, rising to a buzz once
the signal reaches roughly -50 dBm, which is about where a laptop sits on top
of the phone. It lets you sweep a room by ear instead of watching the screen.
Clicks stop when contact goes stale, so silence means no signal rather than no
device.

This is not a Geiger counter, despite sounding a little like one. A counter
clicks once per detected particle and its rate *is* the measurement; here the
rate is computed from the smoothed signal. Packets arrive on a fixed 0.3s
polling timer, so their arrival rate says almost nothing about distance.

Add `--redact` if you are recording the screen. It masks Bluetooth addresses,
and in survey mode replaces discovered device names with the device kind,
since those names are not always yours. A public address is a stable hardware
identifier and, unlike a BLE advertising address, does not rotate, so it is
worth keeping out of a video.

When multiple nearby devices are visible, `findphone --select` enters a compact
numbered list mode and tracks the selected candidate by stable identity.

Two things stay visible deliberately: the name you typed in hunt mode, and the
names in `--list`, because picking a target means reading them. `--list` is
not safe to film even with `--redact`.

Walk slowly and watch the bar. The reading is signal strength in dBm, which is
negative and closer to zero when nearer:

| dBm     | Rough meaning          |
|---------|------------------------|
| -45 up  | arm's reach            |
| -60     | same table             |
| -72     | same room              |
| -85     | far, or behind cover   |
| below   | very far, or shielded  |

Signal strength is a coarse proxy for distance. Metal, walls and human bodies
attenuate it heavily, so a device in a filing cabinet two metres away can read
the same as one fifteen metres away in open air. Trust the trend as you move,
not any single number.

## How it works

Three sources feed one reading, in descending order of quality:

1. **GATT link** — once connected to the device over BLE, `readRSSI()` returns
   a fresh measurement about three times a second. This is the good one.
2. **BLE advertisements** — passively observed. Apple devices rotate their
   advertising addresses roughly every fifteen minutes and only include the
   device name on occasional packets, so this source is sparse.
3. **Classic link RSSI** — read from `system_profiler SPBluetoothDataType`,
   keyed by the stable public address of a paired device.

Source 3 has a trap worth knowing about: macOS refreshes that value only every
three to twelve seconds and serves a cached number in between. Polling it
faster does not yield more information. Measured over 112 polls at 0.4s, every
poll returned a value but the same value repeated for runs of 8 to 31 polls.
The tool therefore counts a measurement only when the value actually changes,
which is why the reported measurement count is far lower than the poll rate —
and honest.

## Permissions

Needs Bluetooth access for whichever terminal runs it, under
System Settings > Privacy & Security > Bluetooth. It will say so if missing.

## Limitations

- Cannot make a device ring. There is no path to that without Find My.
- Cannot give a bearing. One radio yields distance only, not direction.
- Only finds devices with Bluetooth powered on and in range, roughly 10-20 m
  indoors and much less through walls.
