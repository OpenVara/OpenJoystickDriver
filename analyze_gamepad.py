#!/usr/bin/env python3

import sys
import time
import usb.core
import usb.util
import usb.backend.libusb1
from dataclasses import dataclass
from typing import Optional, List, Dict, Tuple

class VENDOR:
    MICROSOFT = 0x045E
    SONY      = 0x054C
    NINTENDO  = 0x057E
    GAMESIR   = 0x3537
    BITDO     = 0x2DC8
    RAZER     = 0x1532
    LOGITECH  = 0x046D

class USB_CLASS:
    PER_INTERFACE = 0x00
    HID           = 0x03
    VENDOR_SPEC   = 0xFF

class EP_TYPE:
    CONTROL     = 0x00
    ISOCHRONOUS = 0x01
    BULK        = 0x02
    INTERRUPT   = 0x03
    NAMES = {0: "Control", 1: "Isochronous", 2: "Bulk", 3: "Interrupt"}

class PROTOCOL:
    GIP     = "GIP"
    PS4     = "PS4/PS5"
    SWITCH  = "Switch"
    HID     = "HID"
    UNKNOWN = "Unknown"

INIT_PACKETS = {
    PROTOCOL.GIP: [
        bytes([0x05, 0x20, 0x00, 0x01, 0x00]),
        bytes([0x0A, 0x20, 0x00, 0x03, 0x00, 0x01, 0x14]),
        bytes([0x06, 0x20, 0x00, 0x02, 0x01, 0x00]),
    ],
    PROTOCOL.PS4: [
        bytes([0x05, 0xFF, 0x05, 0x00, 0x01, 0x00]),
    ],
    PROTOCOL.SWITCH: [
        bytes([0x80, 0x02]),
    ]
}

OUTPUT_TEST_PACKETS = {
    PROTOCOL.GIP:    bytes([0x09, 0x09, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00]), # Rumble/LED
    PROTOCOL.PS4:    bytes([0x05, 0xFF, 0x05, 0x00, 0x01, 0x00]), # LED
    PROTOCOL.SWITCH: bytes([0x80, 0x02]), # LED
}

CONFIG = {
    'READ_TIMEOUT': 100,
    'WRITE_TIMEOUT': 100,
    'MONITOR_DURATION_SEC': 5,
    'MAX_REPORTS': 20,
    'INIT_DELAY_SEC': 0.05,
    'POWER_UNIT_MA': 2,
    'EP_DIR_MASK': 0x80,
    'EP_ATTR_MASK': 0x03,
}

def get_string_safe(dev, index) -> str:
    if not index: return ""
    try: return usb.util.get_string(dev, index)
    except: return "<Unreadable>"

def hex_str(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)

class GamepadAnalyzer:
    def __init__(self, device):
        self.dev = device
        self.vid = device.idVendor
        self.pid = device.idProduct
        self.info = self._collect_info()
        self.protocol = self._detect_protocol()
        self.endpoints = {'in': None, 'out': None}

    def _collect_info(self) -> Dict:
        return {
            'mfg': get_string_safe(self.dev, self.dev.iManufacturer),
            'prod': get_string_safe(self.dev, self.dev.iProduct),
            'serial': get_string_safe(self.dev, self.dev.iSerialNumber) or "N/A"
        }

    def _detect_protocol(self) -> str:
        if self.vid in (VENDOR.GAMESIR, VENDOR.MICROSOFT): return PROTOCOL.GIP
        if self.vid == VENDOR.SONY: return PROTOCOL.PS4
        if self.vid == VENDOR.NINTENDO: return PROTOCOL.SWITCH
        if self.dev.bDeviceClass == USB_CLASS.HID: return PROTOCOL.HID
        return PROTOCOL.UNKNOWN

    def analyze_structure(self):
        print(f"\n[DEVICE] {self.info['prod']} ({self.info['mfg']})")
        print(f"  ID: {self.vid:04X}:{self.pid:04X} | Serial: {self.info['serial']}")
        print(f"  System: Class:0x{self.dev.bDeviceClass:02X} Sub:0x{self.dev.bDeviceSubClass:02X} Proto:0x{self.dev.bDeviceProtocol:02X}")
        print(f"  Detection: {self.protocol}")

        try:
            try:
                self.dev.set_configuration()
            except usb.core.USBError:
                pass

            cfg = self.dev.get_active_configuration()
            print(f"  Config: #{cfg.bConfigurationValue} | Power: {cfg.bMaxPower * CONFIG['POWER_UNIT_MA']}mA")

            for intf in cfg:
                print(f"  [Interface {intf.bInterfaceNumber}] Class: 0x{intf.bInterfaceClass:02X} ({'HID' if intf.bInterfaceClass==USB_CLASS.HID else 'Other'})")

                for ep in intf:
                    addr = ep.bEndpointAddress
                    attr = ep.bmAttributes
                    is_in = (addr & CONFIG['EP_DIR_MASK'])
                    ep_type = EP_TYPE.NAMES.get(attr & CONFIG['EP_ATTR_MASK'], "Unknown")

                    print(f"    {'IN ' if is_in else 'OUT'} 0x{addr:02X} | {ep_type:11} | MaxPkt: {ep.wMaxPacketSize}")

                    direction = 'in' if is_in else 'out'
                    is_interrupt = (attr & CONFIG['EP_ATTR_MASK']) == EP_TYPE.INTERRUPT
                    if is_interrupt or self.endpoints[direction] is None:
                        self.endpoints[direction] = addr

        except usb.core.USBError as e:
            print(f"  [ERROR] Structure analysis failed: {e}")

    def connect_and_test(self):
        if not self._claim_interface():
            return

        self._run_init()
        self._test_output()
        self._monitor_input()

    def _claim_interface(self) -> bool:
        try:
            try:
                if self.dev.is_kernel_driver_active(0):
                    self.dev.detach_kernel_driver(0)
                    print("  [STATUS] Kernel driver detached")
            except (usb.core.USBError, NotImplementedError):
                pass

            try:
                self.dev.set_configuration()
            except usb.core.USBError:
                pass

            usb.util.claim_interface(self.dev, 0)
            print("  [STATUS] Interface claimed successfully")
            return True
        except usb.core.USBError as e:
            print(f"  [ERROR] Connection refused: {e}")
            if "Access denied" in str(e): print("    -> Info: Try running with 'sudo'")
            return False

    def _run_init(self):
        ep = self.endpoints['out']
        pkts = INIT_PACKETS.get(self.protocol, [])
        if not pkts or not ep: return

        print(f"\n[INIT] Sending {self.protocol} Handshake ({len(pkts)} packets)...")
        for i, pkt in enumerate(pkts, 1):
            try:
                self.dev.write(ep, pkt, timeout=CONFIG['WRITE_TIMEOUT'])
                print(f"  -> ({i}/{len(pkts)}) Sent: {hex_str(pkt)}")
                time.sleep(CONFIG['INIT_DELAY_SEC'])
            except usb.core.USBError as e:
                print(f"  -> ({i}/{len(pkts)}) ALERT: Write failed - {e}")

    def _test_output(self):
        ep = self.endpoints['out']
        pkt = OUTPUT_TEST_PACKETS.get(self.protocol)
        if not pkt or not ep: return

        print(f"\n[OUTPUT] Testing Feedback (Rumble/LED)...")
        try:
            self.dev.write(ep, pkt, timeout=CONFIG['WRITE_TIMEOUT'])
            print(f"  -> Sent: {hex_str(pkt)}")
        except usb.core.USBError as e:
            print(f"  -> ALERT: Write failed - {e}")

    def _monitor_input(self):
        ep = self.endpoints['in']
        if not ep:
            print("\n[INPUT] No IN endpoint found, skipping...")
            return

        print(f"\n[INPUT] Monitoring {CONFIG['MAX_REPORTS']} reports (Ctrl+C to stop)...")
        count = 0
        start = time.time()

        try:
            while count < CONFIG['MAX_REPORTS'] and (time.time() - start) < CONFIG['MONITOR_DURATION_SEC']:
                try:
                    data = self.dev.read(ep, 64, timeout=CONFIG['READ_TIMEOUT'])
                    print(f"  [{time.time()-start:5.3f}s] < {hex_str(data)}")
                    count += 1
                except usb.core.USBError:
                    pass
        except KeyboardInterrupt:
            pass

        if count == 0:
            print("  -> No reports received (Try pressing buttons)")

    def close(self):
        try: usb.util.dispose_resources(self.dev)
        except: pass

def list_devices() -> List[usb.core.Device]:
    found = []
    target_vendors = {value for key, value in VENDOR.__dict__.items() if not key.startswith('_')}

    for dev in usb.core.find(find_all=True):
        is_gamepad_class = dev.bDeviceClass in (USB_CLASS.HID, USB_CLASS.VENDOR_SPEC)
        is_known_vendor = dev.idVendor in target_vendors
        if is_gamepad_class or is_known_vendor:
            found.append(dev)
    return found

def main():
    if not usb.backend.libusb1.get_backend():
        print("Error: libusb backend missing.\nMacOS: brew install libusb\nLinux: apt install libusb-1.0-0-dev")
        sys.exit(1)

    devices = list_devices()
    if not devices:
        print("No compatible controllers found")
        sys.exit(0)

    print(f"\nFound {len(devices)} device(s):")
    for i, d in enumerate(devices, 1):
        name = get_string_safe(d, d.iProduct) or "Unknown Device"
        print(f" {i}: {d.idVendor:04X}:{d.idProduct:04X} - {name}")

    try:
        sel = input(f"\nSelect device [1-{len(devices)}]: ")
        idx = int(sel) - 1
        target = devices[idx]
    except (ValueError, IndexError):
        print("Invalid selection")
        sys.exit(1)

    analyzer = GamepadAnalyzer(target)
    try:
        analyzer.analyze_structure()
        analyzer.connect_and_test()
    except KeyboardInterrupt:
        print("\nAborted by user")
    finally:
        analyzer.close()

if __name__ == "__main__":
    main()
