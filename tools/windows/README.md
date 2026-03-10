# Windows USB Analysis Scripts for GameSir G7 SE

Capture real USB/HID data from the G7 SE on Windows to verify GIP parser assumptions,
discover undocumented features, and bring structured reports back to macOS for driver development.

## Prerequisites

- **Python 3.8+** (python.org installer or `winget install Python.Python.3`)
- **GameSir G7 SE** connected via USB
- **Windows 10/11** (tested on LTSC 2021 via Boot Camp)

## Quick Start — Script 1 (No Setup)

`xinput_reader.py` has **zero dependencies** — it uses only ctypes against the built-in `XInput1_4.dll`.

```
python xinput_reader.py                  # Live polling (~120Hz)
python xinput_reader.py --investigate    # Guided button investigation
python xinput_reader.py --record         # Log to JSONL file
python xinput_reader.py --user 1         # Use controller index 1 (0-3)
```

This works immediately with the stock Xbox driver — no Zadig needed.

## Zadig Setup (Scripts 2-4)

Scripts 2-4 need direct USB access via **WinUSB** (replaces the Xbox driver temporarily).

### Install WinUSB Driver

1. Download [Zadig](https://zadig.akeo.ie/) and run it
2. **Options → List All Devices**
3. Select the G7 SE (look for VID `3537` PID `1010`, or "Xbox Controller" / "GameSir")
4. Set the target driver to **WinUSB**
5. Click **Replace Driver** (or Install)
6. Wait for "Driver installed successfully"

> **Note:** While WinUSB is active, the controller won't work as an Xbox gamepad.
> See "Restoring Xbox Driver" below to switch back.

### Install libusb

1. Download `libusb-1.0.dll` from [libusb releases](https://github.com/libusb/libusb/releases)
   - Use the **VS2019** or **MinGW64** 64-bit DLL from the archive
2. Place `libusb-1.0.dll` in the `tools/windows/` directory (next to the scripts)
   - Or anywhere on your `PATH`

### Install pyusb

```
pip install pyusb
```

## Running the Scripts

### Script 2: USB Descriptor Dump

One-shot dump of all USB descriptors to JSON:

```
python usb_descriptor_dump.py
```

Output: `g7se_descriptors_YYYYMMDD_HHMMSS.json`

### Script 3: GIP Packet Capture

Capture raw GIP protocol packets:

```
python gip_capture.py                    # 30s capture (default)
python gip_capture.py --capture          # Unlimited (Ctrl+C to stop)
python gip_capture.py --capture --all    # Show all packets (no diff suppression)
python gip_capture.py --investigate      # Guided button investigation
python gip_capture.py --init-log         # Highlight first 2s (init responses)
```

Output: `g7se_capture_YYYYMMDD_HHMMSS.jsonl`

### Script 4: Rumble, LED & Command Probe

Send commands and record responses:

```
python rumble_probe.py                   # All tests
python rumble_probe.py --rumble          # Rumble tests only
python rumble_probe.py --led             # LED tests only
python rumble_probe.py --probe           # Unknown command probe only
python rumble_probe.py --skip-probe      # Skip unknown commands
```

Output: `g7se_probe_YYYYMMDD_HHMMSS.json`

**Safety:** Each rumble test sends a stop-rumble command afterward. Ctrl+C also sends
a zero-all-motors command before exiting.

## Restoring the Xbox Driver

After you're done with Scripts 2-4, you need to restore the Xbox driver. Simply
unplugging/replugging won't work — Windows caches the WinUSB driver association
per-device and will reinstall WinUSB instead of the Xbox driver. Zadig also can't
help here since it only offers WinUSB/libusb variants, not the original Microsoft
Xbox driver.

**Method 1 — Device Manager with "Delete driver" (try this first):**

1. Open Device Manager → find the controller (under "Universal Serial Bus devices"
   or "libusb-win32 devices")
2. Right-click → **Uninstall device**
3. **Check the box** "Delete the driver software for this device" (Win10) or
   "Attempt to remove the driver for this device" (Win11) — this is the critical step
4. Unplug the controller, wait 5 seconds, replug
5. Windows should now install the Xbox driver from its built-in driver store

**Method 2 — pnputil (if Method 1 fails):**

1. Open an **Admin Command Prompt**
2. `pnputil /enum-drivers` — find the WinUSB OEM driver (look for "WinUSB" or the
   device's VID/PID in the output)
3. `pnputil /delete-driver oemXX.inf /force` — replace `oemXX.inf` with the actual
   filename from step 2
4. Device Manager → right-click the device → Uninstall device
5. Unplug/replug

**Method 3 — Nuclear option (if nothing else works):**

1. Device Manager → View → **Show hidden devices**
2. Uninstall **all** entries for the controller (including greyed-out ones),
   checking "Delete driver" each time
3. Unplug/replug

## Collecting Results

Copy all output files back to macOS for analysis:

```
# From the tools/windows/ directory
copy g7se_*.json \\path\to\shared\folder
copy g7se_*.jsonl \\path\to\shared\folder
```

Expected files:

- `g7se_xinput_*.jsonl` — XInput state log
- `g7se_descriptors_*.json` — USB descriptor dump
- `g7se_capture_*.jsonl` — Raw GIP packets
- `g7se_probe_*.json` — Rumble/LED/command probe results

## Troubleshooting

### "Device not found"

- Is the G7 SE plugged in via USB (not Bluetooth)?
- For Scripts 2-4: did you install WinUSB via Zadig for the correct device?
- Check VID:PID — should be `3537:1010`

### "Cannot claim interface" / "Access denied"

- Close any other apps using the controller (Xbox Accessories, Steam, etc.)
- Run the script as Administrator
- Verify WinUSB is installed (Zadig should show "WinUSB" as current driver)

### "libusb-1.0.dll not found"

- Place the DLL in the same directory as the scripts
- Or add its location to your system `PATH`

### XInput script shows "Controller not connected"

- Make sure the Xbox driver is active (not WinUSB)
- Try a different `--user` index (0-3)
- Replug the controller

### Rumble probe doesn't produce vibration

- Verify the controller works in a game first
- Check that WinUSB is the active driver (rumble commands go via raw USB, not XInput)

## File Overview

| File | Requires Zadig? | Description |
|------|-----------------|-------------|
| `gip_common.py` | — | Shared constants, sequencer, helpers |
| `xinput_reader.py` | No | XInput API polling (zero deps) |
| `usb_descriptor_dump.py` | Yes | Full USB descriptor dump → JSON |
| `gip_capture.py` | Yes | Raw GIP packet capture → JSONL |
| `rumble_probe.py` | Yes | Rumble/LED/command testing → JSON |
