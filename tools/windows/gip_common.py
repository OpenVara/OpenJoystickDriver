"""
gip_common.py - Shared constants, sequencer, and helpers for G7 SE Windows analysis scripts.

Extracted from analyze_gamepad.py (repo root) and adapted for Windows (Zadig/WinUSB).
"""

import os
import sys
import struct
import ctypes
import datetime
from typing import Optional, Dict, List, Tuple

# ── Device ────────────────────────────────────────────────────────────────────
VID_GAMESIR = 0x3537
PID_G7SE    = 0x1010

# ── GIP command names ─────────────────────────────────────────────────────────
GIP_CMD = {
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
}  # type: Dict[int, str]

# ── Endpoints (defaults for G7 SE) ───────────────────────────────────────────
DEFAULT_IN_EP  = 0x82
DEFAULT_OUT_EP = 0x02

# ── Timing ────────────────────────────────────────────────────────────────────
KEEPALIVE_INTERVAL_S = 4.0
READ_TIMEOUT_MS      = 100
WRITE_TIMEOUT_MS     = 1000

# ── Timeout errno values per platform ─────────────────────────────────────────
TIMEOUT_ERRNOS = {60, 110, 10060}  # macOS, Linux, Windows WSAETIMEDOUT


# ── GIP sequence tracker ─────────────────────────────────────────────────────

class GIPSequencer:
    """Per-command sequence number counter (0..255 wrapping)."""

    def __init__(self):
        # type: () -> None
        self._counters = {}  # type: Dict[int, int]

    def next(self, cmd):
        # type: (int) -> int
        n = self._counters.get(cmd, 0)
        self._counters[cmd] = (n + 1) & 0xFF
        return n


# ── Packet helpers ────────────────────────────────────────────────────────────

def hex_str(data):
    # type: (bytes) -> str
    return " ".join("{:02X}".format(b) for b in data)


def diff_str(prev, curr):
    # type: (bytes, bytes) -> str
    """Hex string with bytes that changed from prev shown in [brackets]."""
    parts = []
    for i, b in enumerate(curr):
        if i < len(prev) and prev[i] != b:
            parts.append("[{:02X}]".format(b))
        else:
            parts.append("{:02X}".format(b))
    for b in curr[len(prev):]:
        parts.append("[{:02X}]".format(b))
    return " ".join(parts)


def changed_count(prev, curr):
    # type: (bytes, bytes) -> int
    return sum(1 for i, b in enumerate(curr) if i >= len(prev) or prev[i] != b)


# ── GIP INPUT (CMD=0x20) decoder ─────────────────────────────────────────────

def decode_virtual_key(payload):
    # type: (bytes) -> str
    """Human-readable decode of CMD=0x07 VIRTUAL_KEY payload."""
    if len(payload) < 2:
        return "(short: {})".format(payload.hex())
    state = "PRESSED" if payload[0] else "released"
    code = payload[1]
    known = {0x5B: "Guide/Xbox"}
    name = known.get(code, "UNKNOWN(0x{:02X})".format(code))
    return "{}  key=0x{:02X} ({})  raw={}".format(state, code, name, payload.hex())


def decode_input(payload):
    # type: (bytes) -> str
    """Human-readable summary of a CMD=0x20 input payload."""
    if len(payload) < 14:
        return "(short payload: {} bytes)".format(len(payload))

    b0, b1 = payload[0], payload[1]
    lt = struct.unpack_from("<H", payload, 2)[0]
    rt = struct.unpack_from("<H", payload, 4)[0]
    lsx = struct.unpack_from("<h", payload, 6)[0]
    lsy = struct.unpack_from("<h", payload, 8)[0]
    rsx = struct.unpack_from("<h", payload, 10)[0]
    rsy = struct.unpack_from("<h", payload, 12)[0]

    buttons = []  # type: List[str]
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

    extra_notes = []  # type: List[str]

    if len(payload) >= 15:
        ext14 = payload[14]
        if ext14 & 0x01:
            buttons.append("Share")
        unknown14 = ext14 & 0xFE
        if unknown14:
            extra_notes.append("ext[14]=0x{:02X} (unknown bits!)".format(ext14))

    if len(payload) > 15:
        nonzero = [(i + 15, v) for i, v in enumerate(payload[15:]) if v != 0]
        if nonzero:
            fields = " ".join("[{}]=0x{:02X}".format(i, v) for i, v in nonzero)
            extra_notes.append("NONZERO: {}".format(fields))

    btn_str = "+".join(buttons) if buttons else "idle"
    axes = "LT={} RT={} LS=({},{}) RS=({},{})".format(lt, rt, lsx, lsy, rsx, rsy)
    result = "{}  |  {}".format(btn_str, axes)
    if extra_notes:
        result += "  |  " + "  ".join(extra_notes)
    return result


# ── Windows-specific USB helpers ─────────────────────────────────────────────

def configure_libusb_backend():
    # type: () -> Optional[object]
    """Locate libusb-1.0.dll and configure a pyusb backend. Returns the backend or None."""
    try:
        import usb.backend.libusb1
    except ImportError:
        print("[ERROR] pyusb not installed.  pip install pyusb")
        return None

    # pyusb caches _lib at module level; reset it before each attempt so
    # a previous failed call does not prevent retry with an explicit path.
    lb1 = usb.backend.libusb1

    def _try_backend(find_library=None):
        # type: (object) -> object
        lb1._lib = None  # type: ignore[attr-defined]  # force fresh _setup_backend
        return lb1.get_backend(find_library=find_library)

    # Try default (system PATH / site-packages)
    backend = _try_backend()
    if backend is not None:
        return backend

    # Search common locations for libusb-1.0.dll on Windows
    search_paths = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "libusb-1.0.dll"),
        os.path.join(os.getcwd(), "libusb-1.0.dll"),
    ]
    prog_files = os.environ.get("ProgramFiles", "C:\\Program Files")
    prog_files_x86 = os.environ.get("ProgramFiles(x86)", "C:\\Program Files (x86)")
    for base in [prog_files, prog_files_x86]:
        search_paths.append(os.path.join(base, "libusb-1.0", "MinGW64", "dll", "libusb-1.0.dll"))
        search_paths.append(os.path.join(base, "libusb-1.0", "VS2019", "MS64", "dll", "libusb-1.0.dll"))

    found_path = None  # type: Optional[str]
    for path in search_paths:
        if os.path.isfile(path):
            found_path = path
            print("[INFO] Found DLL at: {}".format(path))
            dll_dir = os.path.dirname(os.path.abspath(path))
            if hasattr(os, "add_dll_directory") and dll_dir:
                os.add_dll_directory(dll_dir)  # Python 3.8+ Windows DLL search path fix
            backend = _try_backend(find_library=lambda _, _p=path: _p)
            if backend is not None:
                print("[INFO] Using libusb from: {}".format(path))
                return backend

            # DLL found, ctypes can load it, but pyusb still refused — diagnose
            print("[ERROR] DLL found but pyusb failed to initialise it: {}".format(path))
            try:
                ctypes.CDLL(path)
                print("  ctypes load: OK")
                print("  pyusb refused it — likely a pyusb internal setup error.")
                print("  Try: pip install --upgrade pyusb")
            except OSError as load_err:
                print("  OS error: {}".format(load_err))
                err_str = str(load_err)
                if "193" in err_str or "%1" in err_str:
                    bits = "64" if sys.maxsize > 2 ** 32 else "32"
                    print("  -> Wrong DLL architecture! Python is {}-bit.".format(bits))
                    print("     Use VS2019/MS{}/dll/libusb-1.0.dll from the release zip.".format(bits))
                elif "126" in err_str or "not found" in err_str.lower():
                    print("  -> DLL has missing dependencies.")
                    print("     Try the MinGW64 build: MinGW64/dll/libusb-1.0.dll")
                    print("     Or install Visual C++ Redistributable 2019.")
            return None

    if found_path is None:
        print("[INFO] libusb-1.0.dll not found in any search path.")
        downloaded = _download_libusb(os.path.dirname(os.path.abspath(__file__)))
        if downloaded == "_pip_installed":
            # pip installed libusb-package — try its backend directly
            try:
                import libusb_package
                backend = libusb_package.get_libusb1_backend()
                if backend is not None:
                    print("[INFO] Using libusb via libusb-package (pip)")
                    return backend
            except ImportError:
                pass
            # fallback: retry default pyusb search (pip may have put DLL on PATH)
            backend = _try_backend()
            if backend is not None:
                return backend
        elif downloaded and os.path.isfile(downloaded):
            # extracted DLL — use explicit path
            dll_dir = os.path.dirname(downloaded)
            if hasattr(os, "add_dll_directory") and dll_dir:
                os.add_dll_directory(dll_dir)
            backend = _try_backend(find_library=lambda _, _p=downloaded: _p)
            if backend is not None:
                print("[INFO] Using libusb from: {}".format(downloaded))
                return backend
            print("[ERROR] Downloaded DLL still failed to load — check architecture.")
        else:
            print("[ERROR] Could not obtain libusb-1.0.dll automatically.")
            print("  Try: pip install libusb-package")
            print("  Or download manually: https://github.com/libusb/libusb/releases")
    return None


def _download_libusb(dest_dir):
    # type: (str) -> Optional[str]
    """
    Obtain libusb-1.0.dll using a two-tier fallback:
      1. pip install libusb-package (returns "_pip_installed" sentinel)
      2. Download .whl from PyPI and extract the DLL (returns DLL path)
    Returns None on failure after printing diagnostics.
    """
    import subprocess

    # ── Tier 1: pip install libusb-package ──────────────────────────────────
    print("[INFO] Attempting: pip install libusb-package ...")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", "libusb-package"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        if result.returncode == 0:
            print("[INFO] libusb-package installed successfully via pip.")
            return "_pip_installed"
        print("[WARN] pip install failed (exit {}). Trying direct download...".format(
            result.returncode
        ))
    except FileNotFoundError:
        print("[WARN] pip not available. Trying direct download...")
    except Exception as e:
        print("[WARN] pip install error: {}. Trying direct download...".format(e))

    # ── Tier 2: download .whl from PyPI and extract DLL ────────────────────
    import urllib.request
    import zipfile
    import io

    is_64 = sys.maxsize > 2 ** 32
    whl_url = (
        "https://files.pythonhosted.org/packages/cd/91/"
        "9eaa00e5e9d2ba0a0adc945990d2383ef3021afa985f59cce975f3c89d20/"
        "libusb_package-1.0.26.1-cp38-cp38-win_amd64.whl"
    ) if is_64 else (
        "https://files.pythonhosted.org/packages/4f/39/"
        "fdce19efd5a4ca7ed7dcdbec70824d871da238e7f222034dce7372dfcb85/"
        "libusb_package-1.0.26.1-cp38-cp38-win32.whl"
    )
    bits = "64" if is_64 else "32"
    dll_name_in_whl = "libusb_package/libusb-1.0.dll"

    print("[INFO] Downloading {}-bit libusb wheel from PyPI...".format(bits))
    try:
        req = urllib.request.Request(whl_url, headers={"User-Agent": "gip_common/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()

        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            names = [n.replace("\\", "/") for n in zf.namelist()]
            if dll_name_in_whl not in names:
                # Try to find any libusb DLL in the wheel
                dll_candidates = [n for n in names if n.endswith("libusb-1.0.dll")]
                if dll_candidates:
                    dll_name_found = dll_candidates[0]
                else:
                    print("[ERROR] libusb-1.0.dll not found in wheel.")
                    print("  Contents (dll): {}".format(
                        [n for n in names if n.endswith(".dll")]
                    ))
                    return None
            else:
                dll_name_found = dll_name_in_whl

            dll_bytes = zf.read(zf.namelist()[names.index(dll_name_found)])

        dest_path = os.path.join(dest_dir, "libusb-1.0.dll")
        with open(dest_path, "wb") as f:
            f.write(dll_bytes)
        print("[INFO] libusb-1.0.dll ({}-bit) saved to: {}".format(bits, dest_path))
        return dest_path

    except Exception as e:
        print("[ERROR] Wheel download failed: {}".format(e))

    # ── Both tiers failed — print diagnostics ──────────────────────────────
    print("")
    print("[ERROR] Could not obtain libusb automatically.")
    print("  Recommended: pip install libusb-package")
    print("")
    # Try to show actual GitHub release assets for manual download
    try:
        api_url = "https://api.github.com/repos/libusb/libusb/releases/latest"
        req = urllib.request.Request(api_url, headers={"User-Agent": "gip_common/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            import json as _json
            release = _json.loads(resp.read().decode())
        tag = release.get("tag_name", "unknown")
        assets = release.get("assets", [])
        if assets:
            print("  Latest GitHub release ({}):".format(tag))
            for asset in assets:
                print("    {} -> {}".format(
                    asset.get("name", "?"),
                    asset.get("browser_download_url", "?"),
                ))
            print("")
            print("  Note: GitHub releases are .7z (needs 7-Zip to extract).")
            print("  Inside the archive, use: VS2019/MS{}/dll/libusb-1.0.dll".format(bits))
    except Exception:
        print("  Manual download: https://github.com/libusb/libusb/releases")
    return None


def find_device_windows():
    # type: () -> Optional[object]
    """Find the G7 SE on Windows using pyusb with libusb backend."""
    import usb.core
    import usb.util

    backend = configure_libusb_backend()
    if backend is None:
        return None

    dev = usb.core.find(idVendor=VID_GAMESIR, idProduct=PID_G7SE, backend=backend)
    if dev is not None:
        return dev

    # Fallback: any vendor-class device that looks like a controller
    for d in usb.core.find(find_all=True, backend=backend):
        if getattr(d, "bDeviceClass", None) == 0xFF:
            try:
                name = usb.util.get_string(d, d.iProduct) or ""
            except Exception:
                name = ""
            if any(s in name.lower() for s in ["xbox", "gamesir", "gamepad", "controller"]):
                return d
    return None


def claim_interface_windows(dev):
    # type: (object) -> bool
    """Claim USB interface 0 on Windows (no kernel driver detach needed with Zadig/WinUSB)."""
    import usb.core
    import usb.util

    try:
        try:
            dev.set_configuration()
        except usb.core.USBError:
            pass
        usb.util.claim_interface(dev, 0)
        return True
    except usb.core.USBError as e:
        err_str = str(e)
        print("[ERROR] Cannot claim interface: {}".format(e))
        if "Access" in err_str or "denied" in err_str:
            print("  -> Run as Administrator")
        elif "busy" in err_str.lower() or "claimed" in err_str.lower():
            print("  -> Another application has the device open.")
            print("     Close any Xbox/gamepad apps and try again.")
        else:
            print("  -> Make sure you have installed the WinUSB driver via Zadig.")
            print("     See README.md for Zadig setup instructions.")
        return False


def get_endpoints(dev):
    # type: (object) -> Tuple[int, int]
    """Return (in_ep_addr, out_ep_addr) for the first interrupt endpoints."""
    import usb.core

    in_ep = None   # type: Optional[int]
    out_ep = None  # type: Optional[int]
    try:
        cfg = dev.get_active_configuration()
    except usb.core.USBError:
        return DEFAULT_IN_EP, DEFAULT_OUT_EP
    for intf in cfg:
        for ep in intf:
            is_in = bool(ep.bEndpointAddress & 0x80)
            is_interrupt = (ep.bmAttributes & 0x03) == 0x03
            if is_interrupt:
                if is_in and in_ep is None:
                    in_ep = ep.bEndpointAddress
                elif not is_in and out_ep is None:
                    out_ep = ep.bEndpointAddress
    return (in_ep or DEFAULT_IN_EP, out_ep or DEFAULT_OUT_EP)


# ── Init / keep-alive ────────────────────────────────────────────────────────

def send_init(dev, out_ep, seq):
    # type: (object, int, GIPSequencer) -> None
    """Send the GIP handshake sequence."""
    import usb.core

    init_packets = [
        bytes([0x05, 0x20, seq.next(0x05), 0x01, 0x00]),
        bytes([0x0A, 0x20, seq.next(0x0A), 0x03, 0x00, 0x01, 0x14]),
        bytes([0x06, 0x20, seq.next(0x06), 0x02, 0x01, 0x00]),
    ]
    print("[INIT] Sending GIP handshake...")
    import time
    for i, pkt in enumerate(init_packets, 1):
        try:
            dev.write(out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
            print("  -> ({}/3) {}".format(i, hex_str(pkt)))
            time.sleep(0.05)
        except usb.core.USBError as e:
            print("  -> ({}/3) FAILED: {}".format(i, e))


def send_keepalive(dev, out_ep, seq):
    # type: (object, int, GIPSequencer) -> bool
    import usb.core
    pkt = bytes([0x03, 0x20, seq.next(0x03), 0x03, 0x00, 0x00, 0x00])
    try:
        dev.write(out_ep, pkt, timeout=WRITE_TIMEOUT_MS)
        return True
    except usb.core.USBError:
        return False


# ── Output helpers ────────────────────────────────────────────────────────────

def make_output_path(prefix, ext):
    # type: (str, str) -> str
    """Generate a timestamped output filename, e.g. g7se_xinput_20260310_143022.jsonl"""
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    return "{}_{}.{}".format(prefix, ts, ext)


def is_timeout_errno(errno_val):
    # type: (Optional[int]) -> bool
    """Check if a USB error errno indicates a timeout (cross-platform)."""
    return errno_val is None or errno_val in TIMEOUT_ERRNOS
