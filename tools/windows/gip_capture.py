#!/usr/bin/env python3
"""
gip_capture.py - Raw GIP packet capture for GameSir G7 SE on Windows.

Adapted from analyze_gamepad.py (repo root) with Windows USB compatibility
and JSONL file logging.

Requires: Python 3.8+, pyusb, libusb-1.0.dll, Zadig (WinUSB driver)

Modes:
  (default)      30s capture with GIP parsing and diff display
  --capture      Unlimited capture until Ctrl+C
  --investigate  Guided per-button investigation
  --all          Show every packet (no diff suppression)
  --init-log     Prominently log first 2s after handshake

Usage:
  python gip_capture.py
  python gip_capture.py --capture --all
  python gip_capture.py --investigate
  python gip_capture.py --capture --init-log
"""

import sys
import time
import json
import datetime
from typing import Optional, Dict, List, Tuple

from gip_common import (
    VID_GAMESIR, PID_G7SE,
    GIP_CMD, GIPSequencer,
    KEEPALIVE_INTERVAL_S, READ_TIMEOUT_MS,
    hex_str, diff_str, changed_count,
    decode_input, decode_virtual_key,
    find_device_windows, claim_interface_windows, get_endpoints,
    send_init, send_keepalive,
    make_output_path, is_timeout_errno,
)


def capture(
    dev,          # usb.core.Device
    in_ep,        # int
    out_ep,       # int
    seq,          # GIPSequencer
    logfile,      # file object or None
    duration=None,     # Optional[float]
    diff_only=True,    # bool
    label="",          # str
    init_log=False,    # bool - highlight first 2s
):
    # type: (...) -> Dict[int, int]
    """
    Capture GIP packets with console display and optional JSONL logging.
    Returns {cmd: count} summary.
    """
    import usb.core

    if label:
        print("\n" + "-" * 60)
        print("  {}".format(label))
        print("-" * 60)

    prev_input = None   # type: Optional[bytes]
    cmd_counts = {}     # type: Dict[int, int]
    start = last_ka = time.time()
    total = 0
    init_phase_logged = False

    try:
        while True:
            now = time.time()
            if duration is not None and (now - start) >= duration:
                break

            elapsed = now - start

            # Init-log phase marker
            if init_log and not init_phase_logged and elapsed >= 2.0:
                print("\n  === END OF INIT PHASE (2.0s) ===\n")
                init_phase_logged = True

            # Keep-alive
            if now - last_ka >= KEEPALIVE_INTERVAL_S:
                send_keepalive(dev, out_ep, seq)
                last_ka = time.time()

            # Read one packet
            try:
                raw = dev.read(in_ep, 64, timeout=READ_TIMEOUT_MS)
                data = bytes(raw)
            except usb.core.USBError as e:
                errno_val = getattr(e, "errno", None)
                if is_timeout_errno(errno_val):
                    continue
                print("\n[ERROR] Read error: {}".format(e))
                break

            if len(data) < 4:
                continue

            cmd = data[0]
            declared_len = data[3]
            payload = data[4:4 + declared_len] if len(data) >= 4 + declared_len else data[4:]
            cmd_counts[cmd] = cmd_counts.get(cmd, 0) + 1
            total += 1
            cmd_name = GIP_CMD.get(cmd, "0x{:02X}".format(cmd))

            # Log to JSONL file
            if logfile is not None:
                record = {
                    "t": round(elapsed, 4),
                    "cmd": cmd,
                    "cmd_name": cmd_name,
                    "raw": data.hex(),
                    "payload": payload.hex(),
                    "len": declared_len,
                }
                logfile.write(json.dumps(record) + "\n")

            # Init phase highlighting
            prefix = "[INIT] " if init_log and elapsed < 2.0 else ""

            # Console display
            if cmd == 0x20:  # INPUT
                if diff_only and prev_input is not None and payload == prev_input:
                    continue
                if prev_input is not None and payload != prev_input:
                    n = changed_count(prev_input, payload)
                    print("{}[{:8.3f}s] INPUT  D{:2d}  {}".format(
                        prefix, elapsed, n, diff_str(prev_input, payload)))
                else:
                    print("{}[{:8.3f}s] INPUT       {}".format(
                        prefix, elapsed, hex_str(payload)))
                print("             ->  {}".format(decode_input(payload)))
                prev_input = payload
            elif cmd == 0x07:  # VIRTUAL_KEY
                print("{}[{:8.3f}s] {:<12} {}".format(
                    prefix, elapsed, cmd_name, hex_str(data)))
                print("             ->  {}".format(decode_virtual_key(payload)))
            else:
                print("{}[{:8.3f}s] {:<12} {}".format(
                    prefix, elapsed, cmd_name, hex_str(data)))

    except KeyboardInterrupt:
        pass

    elapsed_total = time.time() - start
    print("\n  {} packets in {:.1f}s".format(total, elapsed_total))
    if cmd_counts:
        summary = "  CMDs seen: " + "  ".join(
            "{}x{}".format(GIP_CMD.get(k, "0x{:02X}".format(k)), v)
            for k, v in sorted(cmd_counts.items())
        )
        print(summary)

    if logfile is not None:
        logfile.flush()

    return cmd_counts


# ── Investigate mode ──────────────────────────────────────────────────────────

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
    ("REFERENCE - press  A,  LB,  Share,  Guide  (confirm known buttons)", 10.0),
]  # type: List[Tuple[str, float]]


def investigate(dev, in_ep, out_ep, seq, logfile):
    # type: (...) -> None
    print("\n[INVESTIGATE] Guided button investigation")
    print("Keep sticks centred and no buttons held unless instructed.\n")
    input("Press Enter to begin...")

    all_cmds = {}  # type: Dict[int, int]
    for label, dur in INVESTIGATE_PHASES:
        prompt = "\n->  {}  ({:.0f}s - press Enter then act)".format(label, dur)
        input(prompt)
        counts = capture(dev, in_ep, out_ep, seq, logfile,
                         duration=dur, diff_only=False, label=label)
        for cmd, n in counts.items():
            all_cmds[cmd] = all_cmds.get(cmd, 0) + n

    print()
    print("=" * 60)
    print("INVESTIGATION COMPLETE")
    print("=" * 60)
    print("All CMD bytes observed across all phases:")
    for cmd in sorted(all_cmds):
        print("  0x{:02X}  {:<14}  x{}".format(
            cmd, GIP_CMD.get(cmd, "(unknown)"), all_cmds[cmd]))
    print()
    print("If L4/R4/M/Mic produced any packet, it appears above.")
    print("If no new CMDs appeared, the buttons are handled in firmware.")


# ── Entry point ──────────────────────────────────────────────────────────────

def main():
    # type: () -> None
    args = set(sys.argv[1:])
    mode = "capture" if "--capture" in args else \
           "investigate" if "--investigate" in args else "default"
    diff_only = "--all" not in args
    init_log = "--init-log" in args

    print("[GIP CAPTURE] GameSir G7 SE - Windows")
    print()

    dev = find_device_windows()
    if dev is None:
        print("[ERROR] Device {:04X}:{:04X} not found.".format(VID_GAMESIR, PID_G7SE))
        print("  Is the G7 SE connected? Did you install WinUSB via Zadig?")
        sys.exit(1)

    import usb.util

    try:
        prod = usb.util.get_string(dev, dev.iProduct) or "Controller"
    except Exception:
        prod = "Controller"

    print("[DEVICE] {}".format(prod))
    print("  VID:PID = {:04X}:{:04X}".format(dev.idVendor, dev.idProduct))

    if not claim_interface_windows(dev):
        sys.exit(1)
    print("  Interface 0 claimed")

    in_ep, out_ep = get_endpoints(dev)
    print("  Endpoints: IN=0x{:02X}  OUT=0x{:02X}".format(in_ep, out_ep))

    seq = GIPSequencer()
    send_init(dev, out_ep, seq)
    time.sleep(0.2)

    # Open JSONL log file
    logfile_path = make_output_path("g7se_capture", "jsonl")
    print("  Logging to: {}".format(logfile_path))

    logfile = open(logfile_path, "w")
    try:
        if mode == "default":
            print("\n[CAPTURE] 30s capture - press buttons to investigate.")
            if diff_only:
                print("  Idle INPUT packets suppressed. Changed bytes in [brackets].\n")
            capture(dev, in_ep, out_ep, seq, logfile,
                    duration=30.0, diff_only=diff_only, init_log=init_log)

        elif mode == "capture":
            print("\n[CAPTURE] Running until Ctrl+C.")
            if diff_only:
                print("  Idle INPUT packets suppressed. Changed bytes in [brackets].\n")
            capture(dev, in_ep, out_ep, seq, logfile,
                    duration=None, diff_only=diff_only, init_log=init_log)

        elif mode == "investigate":
            investigate(dev, in_ep, out_ep, seq, logfile)

    finally:
        logfile.close()
        print("\n  Log saved: {}".format(logfile_path))
        usb.util.dispose_resources(dev)


if __name__ == "__main__":
    main()
