#!/usr/bin/env python3
"""
xinput_reader.py - XInput state reader for GameSir G7 SE on Windows.

Zero dependencies beyond Python 3.8+ and ctypes (ships with Python).
Reads controller state via XInput1_4.dll, including the Guide button
via undocumented XInputGetStateEx (ordinal 100).

Modes:
  --live         (default) ~120Hz poll, one-line display, print changes
  --investigate  Guided per-button investigation (L4, R4, M, Mic, etc.)
  --record       Continuous JSONL logging to file

Usage:
  python xinput_reader.py
  python xinput_reader.py --investigate
  python xinput_reader.py --record
  python xinput_reader.py --live --user 1    (controller index 0-3)
"""

import sys
import time
import json
import ctypes
import ctypes.wintypes
import datetime
from typing import Optional, Dict, List, Tuple

# ── XInput ctypes structures ─────────────────────────────────────────────────

class XINPUT_GAMEPAD(ctypes.Structure):
    _fields_ = [
        ("wButtons", ctypes.wintypes.WORD),
        ("bLeftTrigger", ctypes.wintypes.BYTE),
        ("bRightTrigger", ctypes.wintypes.BYTE),
        ("sThumbLX", ctypes.c_short),
        ("sThumbLY", ctypes.c_short),
        ("sThumbRX", ctypes.c_short),
        ("sThumbRY", ctypes.c_short),
    ]


class XINPUT_STATE(ctypes.Structure):
    _fields_ = [
        ("dwPacketNumber", ctypes.wintypes.DWORD),
        ("Gamepad", XINPUT_GAMEPAD),
    ]


# ── XInput button bitmasks ───────────────────────────────────────────────────
XINPUT_BUTTONS = {
    0x0001: "DUp",
    0x0002: "DDown",
    0x0004: "DLeft",
    0x0008: "DRight",
    0x0010: "Start",
    0x0020: "Back",
    0x0040: "LSB",
    0x0080: "RSB",
    0x0100: "LB",
    0x0200: "RB",
    0x0400: "Guide",      # only via XInputGetStateEx
    0x1000: "A",
    0x2000: "B",
    0x4000: "X",
    0x8000: "Y",
}  # type: Dict[int, str]


# ── XInput DLL loading ───────────────────────────────────────────────────────

def load_xinput():
    # type: () -> Tuple[ctypes.WinDLL, bool]
    """Load XInput DLL and return (dll, has_ex). Tries XInputGetStateEx (ordinal 100)."""
    dll_names = ["XInput1_4.dll", "XInput1_3.dll", "XInput9_1_0.dll"]
    dll = None
    for name in dll_names:
        try:
            dll = ctypes.WinDLL(name)
            break
        except OSError:
            continue

    if dll is None:
        print("[ERROR] Could not load any XInput DLL.")
        print("  Tried: {}".format(", ".join(dll_names)))
        sys.exit(1)

    # Try undocumented XInputGetStateEx (ordinal 100) for Guide button
    has_ex = False
    try:
        get_state_ex = ctypes.WINFUNCTYPE(
            ctypes.wintypes.DWORD,
            ctypes.wintypes.DWORD,
            ctypes.POINTER(XINPUT_STATE),
        )(100, dll)
        # Test call to verify it works
        test_state = XINPUT_STATE()
        get_state_ex(0, ctypes.byref(test_state))
        dll.XInputGetStateEx = get_state_ex
        has_ex = True
    except Exception:
        pass

    return dll, has_ex


def get_state(dll, has_ex, user_index):
    # type: (ctypes.WinDLL, bool, int) -> Optional[XINPUT_STATE]
    """Read controller state. Returns None if controller not connected."""
    state = XINPUT_STATE()
    if has_ex:
        result = dll.XInputGetStateEx(user_index, ctypes.byref(state))
    else:
        result = dll.XInputGetState(user_index, ctypes.byref(state))

    if result == 0:  # ERROR_SUCCESS
        return state
    return None


def state_to_dict(state):
    # type: (XINPUT_STATE) -> Dict
    """Convert XINPUT_STATE to a plain dict for JSON serialization."""
    gp = state.Gamepad
    buttons_pressed = []
    for mask, name in sorted(XINPUT_BUTTONS.items()):
        if gp.wButtons & mask:
            buttons_pressed.append(name)

    return {
        "packet": state.dwPacketNumber,
        "buttons_raw": gp.wButtons,
        "buttons": buttons_pressed,
        "lt": gp.bLeftTrigger,
        "rt": gp.bRightTrigger,
        "lx": gp.sThumbLX,
        "ly": gp.sThumbLY,
        "rx": gp.sThumbRX,
        "ry": gp.sThumbRY,
    }


def format_oneline(state):
    # type: (XINPUT_STATE) -> str
    """One-line display of controller state."""
    gp = state.Gamepad
    buttons = []
    for mask, name in sorted(XINPUT_BUTTONS.items()):
        if gp.wButtons & mask:
            buttons.append(name)
    btn_str = "+".join(buttons) if buttons else "idle"
    return "Btn={:<30s}  LT={:3d}  RT={:3d}  LS=({:6d},{:6d})  RS=({:6d},{:6d})".format(
        btn_str, gp.bLeftTrigger, gp.bRightTrigger,
        gp.sThumbLX, gp.sThumbLY, gp.sThumbRX, gp.sThumbRY
    )


# ── Comparison table ─────────────────────────────────────────────────────────

def print_comparison_table():
    # type: () -> None
    """Print XInput vs GIP data format comparison."""
    print()
    print("=" * 70)
    print("  XInput vs GIP Protocol Comparison")
    print("=" * 70)
    print("  {:20s} {:20s} {:20s}".format("Field", "XInput", "GIP (raw USB)"))
    print("  " + "-" * 64)
    print("  {:20s} {:20s} {:20s}".format("Left Trigger", "0-255 (8-bit)", "0-1023 (10-bit)"))
    print("  {:20s} {:20s} {:20s}".format("Right Trigger", "0-255 (8-bit)", "0-1023 (10-bit)"))
    print("  {:20s} {:20s} {:20s}".format("Stick X/Y", "-32768..32767", "-32768..32767"))
    print("  {:20s} {:20s} {:20s}".format("Guide button", "Ex only (0x0400)", "CMD=0x07 VK"))
    print("  {:20s} {:20s} {:20s}".format("Share button", "???", "ext byte[14] bit 0"))
    print("  {:20s} {:20s} {:20s}".format("L4/R4/M/Mic", "???", "??? (investigating)"))
    print("=" * 70)
    print()


# ── Modes ─────────────────────────────────────────────────────────────────────

def mode_live(dll, has_ex, user_index):
    # type: (ctypes.WinDLL, bool, int) -> None
    """~120Hz poll with one-line display, print changes with timestamps."""
    print("[LIVE] Polling controller {} at ~120Hz. Ctrl+C to stop.".format(user_index))
    print("  Changes will be printed with timestamps.")
    print()

    last_packet = -1
    start = time.time()

    try:
        while True:
            state = get_state(dll, has_ex, user_index)
            if state is None:
                sys.stdout.write("\r[DISCONNECTED] Controller {} not found. Waiting...".format(user_index))
                sys.stdout.flush()
                time.sleep(0.5)
                continue

            if state.dwPacketNumber != last_packet:
                elapsed = time.time() - start
                line = format_oneline(state)
                sys.stdout.write("\r" + line + "    ")
                sys.stdout.flush()

                if last_packet >= 0:
                    # Print change on new line
                    print()
                    print("[{:8.3f}s] {}".format(elapsed, line))

                last_packet = state.dwPacketNumber

            time.sleep(1.0 / 120)  # ~120Hz
    except KeyboardInterrupt:
        print("\n[DONE] Live mode stopped.")


INVESTIGATE_PHASES = [
    ("BASELINE - all inputs at rest (sticks centred, no buttons)", 6.0),
    ("Press and HOLD  L4  (back left paddle)", 10.0),
    ("Release L4 - rest", 3.0),
    ("Press and HOLD  R4  (back right paddle)", 10.0),
    ("Release R4 - rest", 3.0),
    ("Press and HOLD  M   (mode button, centre back)", 10.0),
    ("Release M - rest", 3.0),
    ("Press and HOLD  Mic (microphone button)", 10.0),
    ("Release Mic - rest", 3.0),
    ("REFERENCE - press  A,  LB,  Start,  Guide  (confirm known buttons)", 10.0),
]  # type: List[Tuple[str, float]]


def mode_investigate(dll, has_ex, user_index):
    # type: (ctypes.WinDLL, bool, int) -> None
    """Guided investigation of each button, checking if it appears in XInput."""
    print("[INVESTIGATE] Guided button investigation via XInput")
    print("Keep sticks centred and no buttons held unless instructed.")
    print()
    input("Press Enter to begin...")

    all_buttons_seen = set()  # type: set

    for label, duration in INVESTIGATE_PHASES:
        prompt = "\n->  {}  ({:.0f}s - press Enter then act)".format(label, duration)
        input(prompt)
        print("  Capturing for {:.0f}s...".format(duration))

        phase_buttons = set()  # type: set
        start = time.time()
        changes = 0
        last_packet = -1

        while (time.time() - start) < duration:
            state = get_state(dll, has_ex, user_index)
            if state is None:
                time.sleep(0.1)
                continue

            if state.dwPacketNumber != last_packet:
                last_packet = state.dwPacketNumber
                changes += 1
                gp = state.Gamepad
                for mask, name in XINPUT_BUTTONS.items():
                    if gp.wButtons & mask:
                        phase_buttons.add(name)
                        all_buttons_seen.add(name)

                elapsed = time.time() - start
                print("  [{:6.2f}s] {}".format(elapsed, format_oneline(state)))

            time.sleep(1.0 / 120)

        print("  Phase done: {} changes, buttons seen: {}".format(
            changes, ", ".join(sorted(phase_buttons)) or "(none)"
        ))

    print()
    print("=" * 60)
    print("INVESTIGATION COMPLETE")
    print("=" * 60)
    print("All XInput buttons detected across all phases:")
    for name in sorted(all_buttons_seen):
        print("  {}".format(name))
    print()
    print("If L4/R4/M/Mic buttons DID appear above, they are mapped in XInput.")
    print("If they did NOT appear, they are either firmware-only or use a")
    print("different API (HID, vendor-specific, or GIP-only).")


def mode_record(dll, has_ex, user_index):
    # type: (ctypes.WinDLL, bool, int) -> None
    """Continuous JSONL recording to file."""
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = "g7se_xinput_{}.jsonl".format(ts)
    print("[RECORD] Logging to {}. Ctrl+C to stop.".format(filename))

    last_packet = -1
    count = 0
    start = time.time()

    try:
        with open(filename, "w") as f:
            while True:
                state = get_state(dll, has_ex, user_index)
                if state is None:
                    time.sleep(0.1)
                    continue

                if state.dwPacketNumber != last_packet:
                    last_packet = state.dwPacketNumber
                    elapsed = time.time() - start
                    record = state_to_dict(state)
                    record["timestamp"] = elapsed
                    f.write(json.dumps(record) + "\n")
                    count += 1

                    if count % 100 == 0:
                        f.flush()
                        sys.stdout.write("\r  {} records ({:.1f}s)".format(count, elapsed))
                        sys.stdout.flush()

                time.sleep(1.0 / 120)
    except KeyboardInterrupt:
        pass

    elapsed_total = time.time() - start
    print("\n[DONE] {} records in {:.1f}s -> {}".format(count, elapsed_total, filename))


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    # type: () -> None
    if sys.platform != "win32":
        print("[ERROR] This script requires Windows (XInput API).")
        sys.exit(1)

    args = sys.argv[1:]
    user_index = 0

    # Parse --user N
    for i, arg in enumerate(args):
        if arg == "--user" and i + 1 < len(args):
            try:
                user_index = int(args[i + 1])
            except ValueError:
                print("[ERROR] --user requires a number 0-3")
                sys.exit(1)

    mode = "live"
    if "--investigate" in args:
        mode = "investigate"
    elif "--record" in args:
        mode = "record"

    dll, has_ex = load_xinput()
    print("[XINPUT] Loaded DLL, XInputGetStateEx: {}".format(
        "available (Guide button supported)" if has_ex else "NOT available"
    ))

    # Check if controller is connected
    state = get_state(dll, has_ex, user_index)
    if state is None:
        print("[WARN] Controller {} not connected. Will wait for connection...".format(user_index))
    else:
        print("[OK] Controller {} connected (packet #{})".format(user_index, state.dwPacketNumber))

    print_comparison_table()

    if mode == "live":
        mode_live(dll, has_ex, user_index)
    elif mode == "investigate":
        mode_investigate(dll, has_ex, user_index)
    elif mode == "record":
        mode_record(dll, has_ex, user_index)


if __name__ == "__main__":
    main()
