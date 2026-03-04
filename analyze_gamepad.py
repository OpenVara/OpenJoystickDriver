#!/usr/bin/env python3
"""
analyze_gamepad.py - Gamesir G7 SE / Xbox GIP raw USB packet analyzer.

Investigates whether L4/R4/M/Mic buttons produce USB traffic.

IMPORTANT: Stop the OpenJoystickDriver daemon before running, or this script
cannot claim the USB interface.
  Stop:  .build/debug/OpenJoystickDriver --headless stop
  Start: .build/debug/OpenJoystickDriver --headless start

Modes:
  (default)      Device info + 30s capture with GIP parsing and diff display
  --capture      Unlimited capture until Ctrl+C
  --investigate  Guided per-button investigation with timed phases
  --all          Show every packet including idle (no diff suppression)

Usage:
  sudo python3 analyze_gamepad.py
  sudo python3 analyze_gamepad.py --capture
  sudo python3 analyze_gamepad.py --investigate
  sudo python3 analyze_gamepad.py --capture --all
"""

import sys
import time
import struct
import usb.core
import usb.util
import usb.backend.libusb1
from typing import Optional, Dict, List, Tuple

# ── Device ────────────────────────────────────────────────────────────────────
VID_GAMESIR = 0x3537
PID_G7SE    = 0x1010

# ── GIP command names ─────────────────────────────────────────────────────────
GIP_CMD: Dict[int, str] = {
    0x01: "ANNOUNCE",
    0x02: "STATUS",
    0x03: "KEEPALIVE",
    0x04: "RECONNECT",
    0x05: "POWER",
    0x06: "AUTHENTICATE",
    0x07: "VIRTUAL_KEY",
    0x09: "RUMBLE",
    0x0A: "LED",
    0x20: "INPUT",
}

# ── Timing ────────────────────────────────────────────────────────────────────
KEEPALIVE_INTERVAL_S = 4.0   # seconds between CMD=0x03 keep-alive packets
READ_TIMEOUT_MS      = 100   # USB read timeout (determines poll rate)
WRITE_TIMEOUT_MS     = 1000  # USB write timeout

# ── GIP sequence tracker ──────────────────────────────────────────────────────

class GIPSequencer:
    """Per-command sequence number counter (0..255 wrapping)."""
    def __init__(self):
        self._counters: Dict[int, int] = {}

    def next(self, cmd: int) -> int:
        n = self._counters.get(cmd, 0)
        self._counters[cmd] = (n + 1) & 0xFF
        return n


# ── Packet helpers ─────────────────────────────────────────────────────────────

def hex_str(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)


def diff_str(prev: bytes, curr: bytes) -> str:
    """Hex string with bytes that changed from prev shown in [brackets]."""
    parts = []
    for i, b in enumerate(curr):
        if i < len(prev) and prev[i] != b:
            parts.append(f"[{b:02X}]")
        else:
            parts.append(f"{b:02X}")
    for b in curr[len(prev):]:          # handle extension in curr
        parts.append(f"[{b:02X}]")
    return " ".join(parts)


def changed_count(prev: bytes, curr: bytes) -> int:
    return sum(1 for i, b in enumerate(curr) if i >= len(prev) or prev[i] != b)


# ── GIP INPUT (CMD=0x20) decoder ──────────────────────────────────────────────

def decode_virtual_key(payload: bytes) -> str:
    """Human-readable decode of CMD=0x07 VIRTUAL_KEY payload."""
    if len(payload) < 2:
        return f"(short: {payload.hex()})"
    state = "PRESSED" if payload[0] else "released"
    code  = payload[1]
    known = {0x5B: "Guide/Xbox"}
    name  = known.get(code, f"UNKNOWN(0x{code:02X})")
    return f"{state}  key=0x{code:02X} ({name})  raw={payload.hex()}"


def decode_input(payload: bytes) -> str:
    """Human-readable summary of a CMD=0x20 input payload."""
    if len(payload) < 14:
        return f"(short payload: {len(payload)} bytes)"

    b0, b1 = payload[0], payload[1]
    lt = struct.unpack_from("<H", payload, 2)[0]
    rt = struct.unpack_from("<H", payload, 4)[0]
    lsx = struct.unpack_from("<h", payload, 6)[0]
    lsy = struct.unpack_from("<h", payload, 8)[0]
    rsx = struct.unpack_from("<h", payload, 10)[0]
    rsy = struct.unpack_from("<h", payload, 12)[0]

    buttons: List[str] = []
    if b0 & 0x04: buttons.append("Start")
    if b0 & 0x08: buttons.append("Back")
    if b0 & 0x10: buttons.append("A")
    if b0 & 0x20: buttons.append("B")
    if b0 & 0x40: buttons.append("X")
    if b0 & 0x80: buttons.append("Y")
    if b1 & 0x01: buttons.append("DUp")
    if b1 & 0x02: buttons.append("DDown")
    if b1 & 0x04: buttons.append("DLeft")
    if b1 & 0x08: buttons.append("DRight")
    if b1 & 0x10: buttons.append("LB")
    if b1 & 0x20: buttons.append("RB")
    if b1 & 0x40: buttons.append("LSB")
    if b1 & 0x80: buttons.append("RSB")

    extra_notes = []

    # Extended byte at payload[14]: bit 0x01 = Share (G7 SE hardware confirmed)
    if len(payload) >= 15:
        ext14 = payload[14]
        if ext14 & 0x01:
            buttons.append("Share")
        unknown14 = ext14 & 0xFE
        if unknown14:
            extra_notes.append(f"ext[14]=0x{ext14:02X} (unknown bits!)")

    # Bytes 15..31 - log any non-zero values (potential unreported buttons)
    if len(payload) > 15:
        nonzero = [(i + 15, v) for i, v in enumerate(payload[15:]) if v != 0]
        if nonzero:
            fields = " ".join(f"[{i}]=0x{v:02X}" for i, v in nonzero)
            extra_notes.append(f"NONZERO: {fields}")

    btn_str = "+".join(buttons) if buttons else "idle"
    axes = f"LT={lt} RT={rt} LS=({lsx},{lsy}) RS=({rsx},{rsy})"
    result = f"{btn_str}  |  {axes}"
    if extra_notes:
        result += "  |  " + "  ".join(extra_notes)
    return result


# ── Device setup ──────────────────────────────────────────────────────────────

def find_device() -> Optional[usb.core.Device]:
    dev = usb.core.find(idVendor=VID_GAMESIR, idProduct=PID_G7SE)
    if dev:
        return dev
    # Fallback: any class-0xFF device (other GIP controllers)
    for d in usb.core.find(find_all=True):
        if getattr(d, 'bDeviceClass', None) == 0xFF:
            try:
                name = usb.util.get_string(d, d.iProduct) or ""
            except Exception:
                name = ""
            if any(s in name.lower() for s in ["xbox", "gamesir", "gamepad", "controller"]):
                return d
    return None


def get_endpoints(dev: usb.core.Device) -> Tuple[int, int]:
    """Return (in_ep_addr, out_ep_addr) for the first interrupt endpoints."""
    in_ep = out_ep = None
    try:
        cfg = dev.get_active_configuration()
    except usb.core.USBError:
        return 0x82, 0x02
    for intf in cfg:
        for ep in intf:
            is_in = bool(ep.bEndpointAddress & 0x80)
            is_interrupt = (ep.bmAttributes & 0x03) == 0x03
            if is_interrupt:
                if is_in and in_ep is None:
                    in_ep = ep.bEndpointAddress
                elif not is_in and out_ep is None:
                    out_ep = ep.bEndpointAddress
    return (in_ep or 0x82, out_ep or 0x02)


def claim_interface(dev: usb.core.Device) -> bool:
    try:
        try:
            if dev.is_kernel_driver_active(0):
                dev.detach_kernel_driver(0)
        except (usb.core.USBError, NotImplementedError):
            pass
        try:
            dev.set_configuration()
        except usb.core.USBError:
            pass
        usb.util.claim_interface(dev, 0)
        return True
    except usb.core.USBError as e:
        print(f"[ERROR] Cannot claim interface: {e}")
        if "13" in str(e) or "Access denied" in str(e) or "busy" in str(e).lower():
            print("  → Run with sudo")
            print("  → Or stop the daemon first:")
            print("      .build/debug/OpenJoystickDriver --headless stop")
        return False


def send_init(dev: usb.core.Device, out_ep: int, seq: GIPSequencer):
    init = [
        bytes([0x05, 0x20, seq.next(0x05), 0x01, 0x00]),
        bytes([0x0A, 0x20, seq.next(0x0A), 0x03, 0x00, 0x01, 0x14]),
        bytes([0x06, 0x20, seq.next(0x06), 0x02, 0x01, 0x00]),
    ]
    print("[INIT] Sending GIP handshake...")
    for i, pkt in enumerate(init, 1):
        try:
            dev.write(out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
            print(f"  → ({i}/3) {hex_str(pkt)}")
            time.sleep(0.05)
        except usb.core.USBError as e:
            print(f"  → ({i}/3) FAILED: {e}")


def send_keepalive(dev: usb.core.Device, out_ep: int, seq: GIPSequencer) -> bool:
    pkt = bytes([0x03, 0x20, seq.next(0x03), 0x03, 0x00, 0x00, 0x00])
    try:
        dev.write(out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
        return True
    except usb.core.USBError:
        return False


# ── Capture loop ──────────────────────────────────────────────────────────────

def capture(
    dev: usb.core.Device,
    in_ep: int,
    out_ep: int,
    seq: GIPSequencer,
    duration: Optional[float] = None,
    diff_only: bool = True,
    label: str = "",
) -> Dict[int, int]:
    """
    Capture GIP packets.

    - All non-INPUT packets are always printed (these are the rare events).
    - INPUT packets: if diff_only, suppress consecutive identical payloads.
      Changed bytes shown in [brackets].
    - keep-alive sent every KEEPALIVE_INTERVAL_S seconds.
    - Returns {cmd: count} summary.
    """
    if label:
        print(f"\n{'─' * 60}")
        print(f"  {label}")
        print(f"{'─' * 60}")

    prev_input: Optional[bytes] = None
    cmd_counts: Dict[int, int] = {}
    start = last_ka = time.time()
    total = 0

    try:
        while True:
            now = time.time()
            if duration is not None and (now - start) >= duration:
                break

            # Keep-alive
            if now - last_ka >= KEEPALIVE_INTERVAL_S:
                send_keepalive(dev, out_ep, seq)
                last_ka = time.time()

            # Read one packet
            try:
                raw = dev.read(in_ep, 64, timeout=READ_TIMEOUT_MS)
                data = bytes(raw)
            except usb.core.USBError as e:
                errno = getattr(e, 'errno', None)
                if errno in (None, 60, 110):   # timeout (60=macOS, 110=Linux)
                    continue
                print(f"\n[ERROR] Read error: {e}")
                break

            if len(data) < 4:
                continue

            cmd = data[0]
            declared_len = int(data[3])
            payload = data[4:4 + declared_len] if len(data) >= 4 + declared_len else data[4:]
            elapsed = now - start
            cmd_counts[cmd] = cmd_counts.get(cmd, 0) + 1
            total += 1
            cmd_name = GIP_CMD.get(cmd, f"0x{cmd:02X}")

            if cmd == 0x20:  # INPUT
                if diff_only and prev_input is not None and payload == prev_input:
                    continue
                if prev_input is not None and payload != prev_input:
                    n = changed_count(prev_input, payload)
                    print(f"[{elapsed:8.3f}s] INPUT  Δ{n:2d}  {diff_str(prev_input, payload)}")
                else:
                    print(f"[{elapsed:8.3f}s] INPUT       {hex_str(payload)}")
                print(f"             ↳  {decode_input(payload)}")
                prev_input = payload
            elif cmd == 0x07:  # VIRTUAL_KEY - always decode in detail
                print(f"[{elapsed:8.3f}s] {cmd_name:<12} {hex_str(data)}")
                print(f"             ↳  {decode_virtual_key(payload)}")
            else:
                # Every non-INPUT packet always printed - this is what we're hunting for
                print(f"[{elapsed:8.3f}s] {cmd_name:<12} {hex_str(data)}")

    except KeyboardInterrupt:
        pass

    elapsed_total = time.time() - start
    print(f"\n  {total} distinct packets in {elapsed_total:.1f}s")
    if cmd_counts:
        summary = "  CMDs seen: " + "  ".join(
            f"{GIP_CMD.get(k, f'0x{k:02X}')}×{v}" for k, v in sorted(cmd_counts.items())
        )
        print(summary)
    return cmd_counts


# ── Investigate mode ──────────────────────────────────────────────────────────

INVESTIGATE_PHASES: List[Tuple[str, float]] = [
    ("BASELINE - all inputs at rest (sticks centred, no buttons)", 6.0),
    ("Press and HOLD  L4  (back left paddle)", 10.0),
    ("Release L4 - rest", 3.0),
    ("Press and HOLD  R4  (back right paddle)", 10.0),
    ("Release R4 - rest", 3.0),
    ("Press and HOLD  M   (mode button, centre back)", 10.0),
    ("Release M - rest", 3.0),
    ("Press and HOLD  Mic (microphone button, near headphone jack)", 10.0),
    ("Release Mic - rest", 3.0),
    ("REFERENCE - press  A,  LB,  Share,  Guide  (confirm known buttons appear)", 10.0),
]


def investigate(dev: usb.core.Device, in_ep: int, out_ep: int, seq: GIPSequencer):
    print("\n[INVESTIGATE] Guided button investigation")
    print("Keep sticks centred and no buttons held unless instructed.\n")
    input("Press Enter to begin...")

    all_cmds: Dict[int, int] = {}
    for label, dur in INVESTIGATE_PHASES:
        prompt = f"\n→  {label}  ({dur:.0f}s - press Enter then act)"
        input(prompt)
        counts = capture(dev, in_ep, out_ep, seq, duration=dur,
                         diff_only=False, label=label)
        for cmd, n in counts.items():
            all_cmds[cmd] = all_cmds.get(cmd, 0) + n

    print("\n" + "═" * 60)
    print("INVESTIGATION COMPLETE")
    print("═" * 60)
    print("All CMD bytes observed across all phases:")
    for cmd in sorted(all_cmds):
        print(f"  0x{cmd:02X}  {GIP_CMD.get(cmd, '(unknown)'):<14}  ×{all_cmds[cmd]}")
    print("\nIf L4/R4/M/Mic produced any packet, it appears above.")
    print("If no new CMDs appeared during those phases, the buttons")
    print("are handled entirely in firmware with no USB traffic.")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    args = set(sys.argv[1:])
    mode = "capture" if "--capture" in args else \
           "investigate" if "--investigate" in args else "default"
    diff_only = "--all" not in args

    if not usb.backend.libusb1.get_backend():
        print("Error: libusb not found.  brew install libusb")
        sys.exit(1)

    dev = find_device()
    if dev is None:
        print(f"Device {VID_GAMESIR:04X}:{PID_G7SE:04X} not found. Is the G7 SE connected?")
        sys.exit(1)

    try:
        prod = usb.util.get_string(dev, dev.iProduct) or "Controller"
    except Exception:
        prod = "Controller"
    try:
        serial = usb.util.get_string(dev, dev.iSerialNumber) or "N/A"
    except Exception:
        serial = "N/A"

    print(f"\n[DEVICE] {prod}")
    print(f"  VID:PID = {dev.idVendor:04X}:{dev.idProduct:04X}  Serial: {serial}")
    print(f"  Class   = 0x{dev.bDeviceClass:02X}")

    # Enumerate ALL interfaces and endpoints so we can spot secondary HID interfaces
    try:
        cfg = dev.get_active_configuration()
        print(f"  Configuration: {cfg.bConfigurationValue}, "
              f"{cfg.bNumInterfaces} interface(s)")
        for intf in cfg:
            cls = intf.bInterfaceClass
            sub = intf.bInterfaceSubClass
            num = intf.bInterfaceNumber
            alt = intf.bAlternateSetting
            cls_name = {0x03: "HID", 0xFF: "Vendor"}.get(cls, f"0x{cls:02X}")
            print(f"    Interface {num} alt={alt}: class={cls_name} sub=0x{sub:02X}")
            for ep in intf:
                direction = "IN " if ep.bEndpointAddress & 0x80 else "OUT"
                xfer = {0x00: "Control", 0x01: "Isoch", 0x02: "Bulk",
                        0x03: "Interrupt"}.get(ep.bmAttributes & 0x03, "?")
                print(f"      EP 0x{ep.bEndpointAddress:02X} {direction} {xfer}"
                      f"  maxPkt={ep.wMaxPacketSize}")
    except Exception as e:
        print(f"  (descriptor enumeration failed: {e})")

    if not claim_interface(dev):
        sys.exit(1)
    print("  Interface 0 claimed")

    in_ep, out_ep = get_endpoints(dev)
    print(f"  Endpoints: IN=0x{in_ep:02X}  OUT=0x{out_ep:02X}")

    seq = GIPSequencer()
    send_init(dev, out_ep, seq)
    time.sleep(0.2)   # let controller settle after init

    try:
        if mode == "default":
            print("\n[CAPTURE] 30s capture - press buttons to investigate.")
            if diff_only:
                print("  Idle INPUT packets suppressed. Changed bytes in [brackets].\n")
            capture(dev, in_ep, out_ep, seq, duration=30.0, diff_only=diff_only)

        elif mode == "capture":
            print("\n[CAPTURE] Running until Ctrl+C.")
            if diff_only:
                print("  Idle INPUT packets suppressed. Changed bytes in [brackets].\n")
            capture(dev, in_ep, out_ep, seq, duration=None, diff_only=diff_only)

        elif mode == "investigate":
            investigate(dev, in_ep, out_ep, seq)

    finally:
        usb.util.dispose_resources(dev)


if __name__ == "__main__":
    main()
