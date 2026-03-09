#!/usr/bin/env python3
"""
rumble_probe.py - Rumble, LED, and command probe for GameSir G7 SE on Windows.

Sends GIP commands and records all responses. Includes rumble motor tests,
LED control, and unknown command probing.

Requires: Python 3.8+, pyusb, libusb-1.0.dll, Zadig (WinUSB driver)

Usage:
  python rumble_probe.py                  # Run all tests
  python rumble_probe.py --rumble         # Rumble tests only
  python rumble_probe.py --led            # LED tests only
  python rumble_probe.py --probe          # Unknown command probe only
  python rumble_probe.py --skip-probe     # All except unknown command probe
"""

import sys
import time
import json
import signal
from typing import Optional, Dict, List, Any

from gip_common import (
    VID_GAMESIR, PID_G7SE,
    GIP_CMD, GIPSequencer,
    KEEPALIVE_INTERVAL_S, READ_TIMEOUT_MS, WRITE_TIMEOUT_MS,
    hex_str,
    find_device_windows, claim_interface_windows, get_endpoints,
    send_init, send_keepalive,
    make_output_path, is_timeout_errno,
)

# ── Rumble packet format ─────────────────────────────────────────────────────
# GIP CMD=0x09 RUMBLE:
# [0x09, 0x20, seq, 0x09, 0x00, activation, lt_motor, rt_motor, left, right, duration, delay, repeat]
#
# activation: 0x03 = main motors (left/right), 0x0C = trigger motors (lt/rt)
#             0x0F = all four motors

RUMBLE_CMD = 0x09
RUMBLE_PAYLOAD_LEN = 0x09

# Known GIP commands to skip during unknown probe
KNOWN_CMDS = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x09, 0x0A, 0x20}


def build_rumble_packet(seq, activation, lt, rt, left, right, duration=32, delay=0, repeat=0):
    # type: (GIPSequencer, int, int, int, int, int, int, int, int) -> bytes
    """Build a rumble command packet."""
    return bytes([
        RUMBLE_CMD, 0x20, seq.next(RUMBLE_CMD), RUMBLE_PAYLOAD_LEN,
        0x00,       # sub-command
        activation,
        lt & 0xFF, rt & 0xFF,
        left & 0xFF, right & 0xFF,
        duration & 0xFF, delay & 0xFF, repeat & 0xFF,
    ])


def build_stop_rumble(seq):
    # type: (GIPSequencer) -> bytes
    """Build a packet that stops all rumble motors."""
    return build_rumble_packet(seq, 0x0F, 0, 0, 0, 0, 0, 0, 0)


def send_and_collect(dev, in_ep, out_ep, packet, collect_time=0.5):
    # type: (Any, int, int, bytes, float) -> List[Dict[str, Any]]
    """Send a packet and collect responses for collect_time seconds."""
    import usb.core

    responses = []  # type: List[Dict[str, Any]]
    try:
        dev.write(out_ep, packet, timeout=WRITE_TIMEOUT_MS)
    except usb.core.USBError as e:
        return [{"error": "write_failed", "detail": str(e)}]

    start = time.time()
    while (time.time() - start) < collect_time:
        try:
            raw = dev.read(in_ep, 64, timeout=READ_TIMEOUT_MS)
            data = bytes(raw)
            if len(data) >= 4:
                cmd = data[0]
                responses.append({
                    "t": round(time.time() - start, 4),
                    "cmd": cmd,
                    "cmd_name": GIP_CMD.get(cmd, "0x{:02X}".format(cmd)),
                    "raw": data.hex(),
                })
        except usb.core.USBError as e:
            if is_timeout_errno(getattr(e, "errno", None)):
                continue
            break

    return responses


class RumbleProbe:
    """Orchestrates rumble, LED, and command probe tests."""

    def __init__(self, dev, in_ep, out_ep, seq):
        # type: (Any, int, int, GIPSequencer) -> None
        self.dev = dev
        self.in_ep = in_ep
        self.out_ep = out_ep
        self.seq = seq
        self.results = []  # type: List[Dict[str, Any]]
        self._last_ka = time.time()

    def _maybe_keepalive(self):
        # type: () -> None
        now = time.time()
        if now - self._last_ka >= KEEPALIVE_INTERVAL_S:
            send_keepalive(self.dev, self.out_ep, self.seq)
            self._last_ka = time.time()

    def _stop_rumble(self):
        # type: () -> None
        """Send stop-rumble to zero all motors."""
        pkt = build_stop_rumble(self.seq)
        try:
            self.dev.write(self.out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
        except Exception:
            pass
        time.sleep(0.1)

    def _run_test(self, name, packet, pause_after=1.0, collect_time=0.5):
        # type: (str, bytes, float, float) -> Dict[str, Any]
        """Run a single test: send packet, collect responses, stop rumble."""
        self._maybe_keepalive()
        print("  [TEST] {}".format(name))
        print("         TX: {}".format(hex_str(packet)))

        responses = send_and_collect(self.dev, self.in_ep, self.out_ep, packet, collect_time)

        non_input = [r for r in responses if r.get("cmd") != 0x20]
        if non_input:
            for r in non_input:
                print("         RX: {} {}".format(r.get("cmd_name", "?"), r.get("raw", "")))
        else:
            print("         RX: (input packets only)")

        result = {
            "test": name,
            "tx": packet.hex(),
            "responses": responses,
            "response_count": len(responses),
            "non_input_responses": len(non_input),
        }
        self.results.append(result)

        self._stop_rumble()
        time.sleep(pause_after)
        return result

    # ── Rumble tests ─────────────────────────────────────────────────────────

    def test_rumble(self):
        # type: () -> None
        print("\n[RUMBLE TESTS]")
        print("=" * 50)

        # Individual motors
        tests = [
            ("Left motor only (128)", 0x03, 0, 0, 128, 0),
            ("Right motor only (128)", 0x03, 0, 0, 0, 128),
            ("Both main motors (128)", 0x03, 0, 0, 128, 128),
            ("Left trigger motor (128)", 0x0C, 128, 0, 0, 0),
            ("Right trigger motor (128)", 0x0C, 0, 128, 0, 0),
            ("Both trigger motors (128)", 0x0C, 128, 128, 0, 0),
            ("All four motors (128)", 0x0F, 128, 128, 128, 128),
        ]

        for name, activation, lt, rt, left, right in tests:
            pkt = build_rumble_packet(self.seq, activation, lt, rt, left, right)
            self._run_test(name, pkt)

        # Intensity sweep
        print("\n  [SWEEP] Left motor intensity 0->255")
        for intensity in range(0, 256, 25):
            pkt = build_rumble_packet(self.seq, 0x03, 0, 0, intensity, 0)
            self._run_test(
                "Left motor intensity={}".format(intensity),
                pkt, pause_after=0.5,
            )

        self._stop_rumble()
        print("  [OK] Rumble tests complete\n")

    # ── LED tests ────────────────────────────────────────────────────────────

    def test_led(self):
        # type: () -> None
        print("\n[LED TESTS]")
        print("=" * 50)

        # CMD=0x0A LED control
        # Format: [0x0A, 0x20, seq, payload_len, ...]
        # Known patterns from Xbox controllers:
        led_tests = [
            ("LED standard (0x01 - dim)", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x01, 0x14])),
            ("LED brightness 0x00 (off?)", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x00, 0x00])),
            ("LED brightness 0x08 (low)", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x01, 0x08])),
            ("LED brightness 0x14 (default)", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x01, 0x14])),
            ("LED brightness 0x28 (high)", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x01, 0x28])),
            ("LED brightness 0xFF (max)", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x01, 0xFF])),
            ("LED pattern 0x02", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x02, 0x14])),
            ("LED pattern 0x03", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x03, 0x14])),
            ("LED pattern 0x04", bytes([0x0A, 0x20, 0, 0x03, 0x00, 0x04, 0x14])),
        ]

        for name, pkt_template in led_tests:
            # Fix sequence number
            pkt = bytearray(pkt_template)
            pkt[2] = self.seq.next(0x0A)
            self._run_test(name, bytes(pkt), pause_after=1.5)

        # Restore default
        restore = bytearray([0x0A, 0x20, self.seq.next(0x0A), 0x03, 0x00, 0x01, 0x14])
        self._run_test("LED restore default", bytes(restore))
        print("  [OK] LED tests complete\n")

    # ── Unknown command probe ────────────────────────────────────────────────

    def test_unknown_commands(self):
        # type: () -> None
        print("\n[UNKNOWN COMMAND PROBE]")
        print("=" * 50)
        print("  Sending minimal packets for CMDs 0x01-0x1F (skipping known).")
        print("  Looking for any response besides INPUT...\n")

        for cmd in range(0x01, 0x20):
            if cmd in KNOWN_CMDS:
                continue

            self._maybe_keepalive()

            # Minimal packet: [cmd, 0x20, seq, 0x01, 0x00]
            pkt = bytes([cmd, 0x20, self.seq.next(cmd), 0x01, 0x00])
            result = self._run_test(
                "CMD 0x{:02X} probe".format(cmd),
                pkt, pause_after=0.3, collect_time=0.3,
            )

            if result["non_input_responses"] > 0:
                print("         *** GOT NON-INPUT RESPONSE for CMD 0x{:02X}! ***".format(cmd))

        print("  [OK] Unknown command probe complete\n")


def main():
    # type: () -> None
    args = set(sys.argv[1:])

    run_rumble = "--rumble" in args or ("--led" not in args and "--probe" not in args)
    run_led = "--led" in args or ("--rumble" not in args and "--probe" not in args)
    run_probe = "--probe" in args or (
        "--rumble" not in args and "--led" not in args and "--skip-probe" not in args
    )

    if "--skip-probe" in args:
        run_probe = False

    print("[RUMBLE PROBE] GameSir G7 SE - Windows")
    print("  Tests: rumble={} led={} probe={}".format(run_rumble, run_led, run_probe))
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
    time.sleep(0.5)

    # Drain initial responses
    import usb.core as _usb_core
    drain_start = time.time()
    while (time.time() - drain_start) < 1.0:
        try:
            dev.read(in_ep, 64, timeout=READ_TIMEOUT_MS)
        except _usb_core.USBError:
            break

    probe = RumbleProbe(dev, in_ep, out_ep, seq)

    # Ctrl-C handler: stop all rumble before exiting
    def signal_handler(sig, frame):
        print("\n[CTRL-C] Stopping all rumble motors...")
        pkt = build_stop_rumble(probe.seq)
        try:
            dev.write(out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
        except Exception:
            pass
        # Save partial results
        _save_results(probe.results)
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    try:
        if run_rumble:
            probe.test_rumble()
        if run_led:
            probe.test_led()
        if run_probe:
            probe.test_unknown_commands()
    finally:
        # Always stop rumble on exit
        pkt = build_stop_rumble(seq)
        try:
            dev.write(out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
        except Exception:
            pass

    _save_results(probe.results)

    try:
        usb.util.dispose_resources(dev)
    except Exception:
        pass


def _save_results(results):
    # type: (List[Dict[str, Any]]) -> None
    outfile = make_output_path("g7se_probe", "json")
    output = {
        "tool": "rumble_probe.py",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "tests": results,
        "summary": {
            "total_tests": len(results),
            "tests_with_responses": sum(
                1 for r in results if r.get("non_input_responses", 0) > 0
            ),
        },
    }
    with open(outfile, "w") as f:
        json.dump(output, f, indent=2)
    print("\n[DONE] Results saved to {}".format(outfile))


if __name__ == "__main__":
    main()
