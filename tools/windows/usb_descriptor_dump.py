#!/usr/bin/env python3
"""
usb_descriptor_dump.py - Full USB descriptor dump for GameSir G7 SE.

One-shot script that captures all USB descriptors and writes them to a
single JSON file for analysis on macOS.

Requires: Python 3.8+, pyusb, libusb-1.0.dll, Zadig (WinUSB driver)

Usage:
  python usb_descriptor_dump.py
"""

import sys
import json
import datetime
from typing import Optional, Dict, List, Any

# Lazy imports so gip_common errors are clear
from gip_common import (
    VID_GAMESIR, PID_G7SE,
    find_device_windows, claim_interface_windows,
    make_output_path,
)


def dump_endpoint(ep):
    # type: (Any) -> Dict[str, Any]
    direction = "IN" if ep.bEndpointAddress & 0x80 else "OUT"
    xfer_types = {0x00: "Control", 0x01: "Isochronous", 0x02: "Bulk", 0x03: "Interrupt"}
    return {
        "address": "0x{:02X}".format(ep.bEndpointAddress),
        "direction": direction,
        "transfer_type": xfer_types.get(ep.bmAttributes & 0x03, "Unknown"),
        "max_packet_size": ep.wMaxPacketSize,
        "interval": ep.bInterval,
        "bmAttributes": "0x{:02X}".format(ep.bmAttributes),
    }


def dump_interface(intf):
    # type: (Any) -> Dict[str, Any]
    class_names = {0x01: "Audio", 0x03: "HID", 0xFF: "Vendor-Specific"}
    return {
        "number": intf.bInterfaceNumber,
        "alternate_setting": intf.bAlternateSetting,
        "class": "0x{:02X}".format(intf.bInterfaceClass),
        "class_name": class_names.get(intf.bInterfaceClass, "Unknown"),
        "subclass": "0x{:02X}".format(intf.bInterfaceSubClass),
        "protocol": "0x{:02X}".format(intf.bInterfaceProtocol),
        "num_endpoints": intf.bNumEndpoints,
        "endpoints": [dump_endpoint(ep) for ep in intf],
    }


def dump_configuration(cfg):
    # type: (Any) -> Dict[str, Any]
    return {
        "value": cfg.bConfigurationValue,
        "num_interfaces": cfg.bNumInterfaces,
        "max_power_mA": cfg.bMaxPower * 2,
        "self_powered": bool(cfg.bmAttributes & 0x40),
        "remote_wakeup": bool(cfg.bmAttributes & 0x20),
        "bmAttributes": "0x{:02X}".format(cfg.bmAttributes),
        "interfaces": [dump_interface(intf) for intf in cfg],
    }


def get_string_safe(dev, index):
    # type: (Any, int) -> Optional[str]
    """Safely read a USB string descriptor."""
    import usb.util
    if index == 0:
        return None
    try:
        return usb.util.get_string(dev, index)
    except Exception:
        return None


def try_hid_report_descriptor(dev, interface_number):
    # type: (Any, int) -> Optional[str]
    """Attempt to read HID report descriptor via control transfer."""
    import usb.core
    try:
        # GET_DESCRIPTOR, type=0x22 (HID Report), wIndex=interface
        data = dev.ctrl_transfer(
            0x81,   # bmRequestType: Device-to-host, Standard, Interface
            0x06,   # bRequest: GET_DESCRIPTOR
            0x2200, # wValue: HID Report descriptor type (0x22) << 8 | index 0
            interface_number,
            4096,   # wLength
            timeout=2000,
        )
        return " ".join("{:02X}".format(b) for b in data)
    except Exception as e:
        return "Error: {}".format(str(e))


def main():
    # type: () -> None
    print("[USB DESCRIPTOR DUMP] GameSir G7 SE")
    print()

    dev = find_device_windows()
    if dev is None:
        print("[ERROR] Device {:04X}:{:04X} not found.".format(VID_GAMESIR, PID_G7SE))
        print("  Is the G7 SE connected? Did you install WinUSB via Zadig?")
        sys.exit(1)

    import usb.util

    # ── Device descriptor ────────────────────────────────────────────────────
    result = {
        "dump_timestamp": datetime.datetime.now().isoformat(),
        "tool": "usb_descriptor_dump.py",
        "device": {
            "vid": "0x{:04X}".format(dev.idVendor),
            "pid": "0x{:04X}".format(dev.idProduct),
            "vid_decimal": dev.idVendor,
            "pid_decimal": dev.idProduct,
            "bcdUSB": "0x{:04X}".format(dev.bcdUSB),
            "bcdDevice": "0x{:04X}".format(dev.bcdDevice),
            "device_class": "0x{:02X}".format(dev.bDeviceClass),
            "device_subclass": "0x{:02X}".format(dev.bDeviceSubClass),
            "device_protocol": "0x{:02X}".format(dev.bDeviceProtocol),
            "max_packet_size0": dev.bMaxPacketSize0,
            "manufacturer": get_string_safe(dev, dev.iManufacturer),
            "product": get_string_safe(dev, dev.iProduct),
            "serial_number": get_string_safe(dev, dev.iSerialNumber),
            "num_configurations": dev.bNumConfigurations,
        },
        "configurations": [],
        "string_descriptors": {},
        "hid_report_descriptors": {},
    }  # type: Dict[str, Any]

    # ── Configuration descriptors ────────────────────────────────────────────
    try:
        cfg = dev.get_active_configuration()
        cfg_data = dump_configuration(cfg)
        result["configurations"].append(cfg_data)

        print("  Device: {} (VID={}, PID={})".format(
            result["device"]["product"] or "Unknown",
            result["device"]["vid"],
            result["device"]["pid"],
        ))
        print("  bcdUSB={}, Class={}".format(
            result["device"]["bcdUSB"],
            result["device"]["device_class"],
        ))
        print("  {} interface(s)".format(cfg.bNumInterfaces))

        # ── HID report descriptors ───────────────────────────────────────────
        for intf in cfg:
            print("    Interface {}: class={} sub=0x{:02X}".format(
                intf.bInterfaceNumber,
                {0x03: "HID", 0xFF: "Vendor"}.get(intf.bInterfaceClass,
                                                    "0x{:02X}".format(intf.bInterfaceClass)),
                intf.bInterfaceSubClass,
            ))
            if intf.bInterfaceClass == 0x03:  # HID
                print("      -> Attempting HID report descriptor read...")
                if not claim_interface_windows(dev):
                    result["hid_report_descriptors"][str(intf.bInterfaceNumber)] = "Error: could not claim interface"
                else:
                    desc = try_hid_report_descriptor(dev, intf.bInterfaceNumber)
                    result["hid_report_descriptors"][str(intf.bInterfaceNumber)] = desc
                    if desc and not desc.startswith("Error"):
                        print("      -> Got {} bytes".format(len(desc.split())))
                    else:
                        print("      -> {}".format(desc))

    except Exception as e:
        print("  [WARN] Could not read configuration: {}".format(e))
        result["configurations"].append({"error": str(e)})

    # ── String descriptors (indices 1-10) ────────────────────────────────────
    print("  Reading string descriptors 1-10...")
    for idx in range(1, 11):
        val = get_string_safe(dev, idx)
        if val is not None:
            result["string_descriptors"][str(idx)] = val
            print("    String {}: {}".format(idx, val))

    # ── Write output ─────────────────────────────────────────────────────────
    outfile = make_output_path("g7se_descriptors", "json")
    with open(outfile, "w") as f:
        json.dump(result, f, indent=2)

    print()
    print("[DONE] Descriptors saved to {}".format(outfile))

    try:
        usb.util.dispose_resources(dev)
    except Exception:
        pass


if __name__ == "__main__":
    main()
