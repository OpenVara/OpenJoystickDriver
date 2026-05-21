#!/usr/bin/env python3
"""Generate the deterministic OpenJoystickDriver DMG background PNG."""

import struct
import sys
import zlib

WIDTH = 660
HEIGHT = 400
SCALE = 2

FONT = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "J": ("00111", "00010", "00010", "00010", "10010", "10010", "01100"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "a": ("00000", "00000", "01110", "00001", "01111", "10001", "01111"),
    "c": ("00000", "00000", "01110", "10000", "10000", "10001", "01110"),
    "d": ("00001", "00001", "01111", "10001", "10001", "10001", "01111"),
    "e": ("00000", "00000", "01110", "10001", "11111", "10000", "01110"),
    "i": ("00100", "00000", "01100", "00100", "00100", "00100", "01110"),
    "k": ("10000", "10010", "10100", "11000", "10100", "10010", "10001"),
    "l": ("01100", "00100", "00100", "00100", "00100", "00100", "01110"),
    "n": ("00000", "00000", "11110", "10001", "10001", "10001", "10001"),
    "o": ("00000", "00000", "01110", "10001", "10001", "10001", "01110"),
    "p": ("00000", "00000", "11110", "10001", "11110", "10000", "10000"),
    "r": ("00000", "00000", "10110", "11001", "10000", "10000", "10000"),
    "s": ("00000", "00000", "01111", "10000", "01110", "00001", "11110"),
    "t": ("00100", "00100", "11111", "00100", "00100", "00101", "00010"),
    "v": ("00000", "00000", "10001", "10001", "10001", "01010", "00100"),
    "y": ("00000", "00000", "10001", "10001", "01111", "00001", "01110"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
}


def chunk(kind, data):
    payload = kind + data
    return (
        struct.pack(">I", len(data))
        + payload
        + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
    )


def in_text(x, y, text, left, top):
    cursor = left
    for char in text:
        if char == " ":
            cursor += 4 * SCALE
            continue
        glyph = FONT.get(char)
        if glyph is None:
            cursor += 6 * SCALE
            continue
        gx = x - cursor
        gy = y - top
        if 0 <= gx < 5 * SCALE and 0 <= gy < 7 * SCALE:
            if glyph[gy // SCALE][gx // SCALE] == "1":
                return True
        cursor += 6 * SCALE
    return False


def pixel(x, y):
    bg = (245, 247, 250)
    arrow = (45, 98, 180)
    text = (40, 40, 40)

    # Large right arrow shaft and head from app icon to Applications.
    if 285 <= x <= 430 and 188 <= y <= 212:
        return arrow
    if 410 <= x <= 470 and abs(y - 200) <= (470 - x) * 0.55:
        return arrow

    # Text labels and simple underline blocks below Finder icon locations.
    if in_text(x, y, "OpenJoystickDriver.app", 84, 310):
        return text
    if in_text(x, y, "Applications", 462, 310):
        return text
    if 100 <= x <= 220 and 285 <= y <= 292:
        return text
    if 465 <= x <= 585 and 285 <= y <= 292:
        return text
    return bg


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: ojd-dmg-background.py <output.png>")
    rows = []
    for y in range(HEIGHT):
        row = bytearray([0])
        for x in range(WIDTH):
            row.extend(pixel(x, y))
        rows.append(bytes(row))
    raw = b"".join(rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(sys.argv[1], "wb") as fh:
        fh.write(png)


if __name__ == "__main__":
    main()
