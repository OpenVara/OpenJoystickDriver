#ifndef GAMEPAD_HID_DESCRIPTOR_H
#define GAMEPAD_HID_DESCRIPTOR_H

#include <stdint.h>

/*
 * Xbox One S-compatible HID gamepad report descriptor.
 *
 * Matches the real Xbox One S Bluetooth HID layout so that Chrome, Safari,
 * SDL, and GCController apply correct device-specific mapping for VID/PID
 * 0x045E:0x02EA.
 *
 * Report layout (15 bytes total):
 *   Bytes 0-1  : Button bitmask, buttons 1-15 + 1-bit pad (LSB = button 1)
 *   Bytes 2-3  : Left Stick X  (Int16 LE, -32767...32767) -- Usage: X  (0x30)
 *   Bytes 4-5  : Left Stick Y  (Int16 LE, -32767...32767) -- Usage: Y  (0x31)
 *   Bytes 6-7  : Left Trigger  (Int16 LE, 0...32767)      -- Usage: Z  (0x32)
 *   Bytes 8-9  : Right Stick X (Int16 LE, -32767...32767) -- Usage: Rx (0x33)
 *   Bytes 10-11: Right Stick Y (Int16 LE, -32767...32767) -- Usage: Ry (0x34)
 *   Bytes 12-13: Right Trigger (Int16 LE, 0...32767)      -- Usage: Rz (0x35)
 *   Byte  14   : Hat switch (low nibble, 1-8 = direction, 0 = neutral) + 4-bit pad
 */

/* clang-format off */
static const uint8_t GAMEPAD_HID_REPORT_DESCRIPTOR[] = {
    /* Usage Page: Generic Desktop */
    0x05, 0x01,
    /* Usage: Gamepad */
    0x09, 0x05,
    /* Collection: Application */
    0xA1, 0x01,
    /* Collection: Physical */
    0xA1, 0x00,

    /* 15 digital buttons (Xbox One S BT order, Button page, usages 1-15) */
    /* b0=A, b1=B, b2=X, b3=Y, b4=LB, b5=RB, b6=L3, b7=R3,             */
    /* b8=Menu, b9=View, b10=Guide, b11=DUp, b12=DDn, b13=DLt, b14=DRt  */
    0x05, 0x09,  /* Usage Page: Button */
    0x19, 0x01,  /* Usage Minimum: 1 */
    0x29, 0x0F,  /* Usage Maximum: 15 */
    0x15, 0x00,  /* Logical Minimum: 0 */
    0x25, 0x01,  /* Logical Maximum: 1 */
    0x75, 0x01,  /* Report Size: 1 */
    0x95, 0x0F,  /* Report Count: 15 */
    0x81, 0x02,  /* Input: Data, Variable, Absolute */

    /* 1-bit pad to round buttons to 16 bits */
    0x75, 0x01,  /* Report Size: 1 */
    0x95, 0x01,  /* Report Count: 1 */
    0x81, 0x03,  /* Input: Constant */

    /* All 6 axes on Generic Desktop — macOS sorts by (page, usage_id),
     * so sharing one page preserves SDL/Chrome axis index order. */
    0x05, 0x01,  /* Usage Page: Generic Desktop */

    /* Left stick: X(0x30), Y(0x31) -- signed */
    0x09, 0x30,  /* Usage: X  (left stick X) */
    0x09, 0x31,  /* Usage: Y  (left stick Y) */
    0x16, 0x01, 0x80,  /* Logical Minimum: -32767 */
    0x26, 0xFF, 0x7F,  /* Logical Maximum:  32767 */
    0x75, 0x10,  /* Report Size: 16 */
    0x95, 0x02,  /* Report Count: 2 */
    0x81, 0x02,  /* Input: Data, Variable, Absolute */

    /* Left trigger: Z(0x32) -- unsigned */
    0x09, 0x32,  /* Usage: Z  (left trigger) */
    0x15, 0x00,  /* Logical Minimum: 0 */
    0x26, 0xFF, 0x7F,  /* Logical Maximum: 32767 */
    0x75, 0x10,  /* Report Size: 16 */
    0x95, 0x01,  /* Report Count: 1 */
    0x81, 0x02,  /* Input: Data, Variable, Absolute */

    /* Right stick: Rx(0x33), Ry(0x34) -- signed */
    0x09, 0x33,  /* Usage: Rx (right stick X) */
    0x09, 0x34,  /* Usage: Ry (right stick Y) */
    0x16, 0x01, 0x80,  /* Logical Minimum: -32767 */
    0x26, 0xFF, 0x7F,  /* Logical Maximum:  32767 */
    0x75, 0x10,  /* Report Size: 16 */
    0x95, 0x02,  /* Report Count: 2 */
    0x81, 0x02,  /* Input: Data, Variable, Absolute */

    /* Right trigger: Rz(0x35) -- unsigned */
    0x09, 0x35,  /* Usage: Rz (right trigger) */
    0x15, 0x00,  /* Logical Minimum: 0 */
    0x26, 0xFF, 0x7F,  /* Logical Maximum: 32767 */
    0x75, 0x10,  /* Report Size: 16 */
    0x95, 0x01,  /* Report Count: 1 */
    0x81, 0x02,  /* Input: Data, Variable, Absolute */

    /* Hat switch (D-pad, 4-bit nibble, Null State, 1-based) */
    0x05, 0x01,  /* Usage Page: Generic Desktop */
    0x09, 0x39,  /* Usage: Hat Switch */
    0x15, 0x01,  /* Logical Minimum: 1 */
    0x25, 0x08,  /* Logical Maximum: 8 */
    0x35, 0x00,  /* Physical Minimum: 0 */
    0x46, 0x3B, 0x01,  /* Physical Maximum: 315 */
    0x66, 0x14, 0x00,  /* Unit: English Rotation (degrees) */
    0x75, 0x04,  /* Report Size: 4 */
    0x95, 0x01,  /* Report Count: 1 */
    0x81, 0x42,  /* Input: Data, Variable, Absolute, Null State */

    /* 4-bit pad to byte-align the hat nibble */
    0x75, 0x04,  /* Report Size: 4 */
    0x95, 0x01,  /* Report Count: 1 */
    0x81, 0x03,  /* Input: Constant */

    /* 15-byte output report (daemon -> dext relay) */
    0x09, 0x01,  /* Usage: Pointer (generic output usage) */
    0x15, 0x00,  /* Logical Minimum: 0 */
    0x26, 0xFF, 0x00,  /* Logical Maximum: 255 */
    0x75, 0x08,  /* Report Size: 8 */
    0x95, 0x0F,  /* Report Count: 15 */
    0x91, 0x02,  /* Output: Data, Variable, Absolute */

    0xC0,  /* End Collection (Physical) */
    0xC0,  /* End Collection (Application) */
};
/* clang-format on */

static const uint32_t GAMEPAD_HID_REPORT_DESCRIPTOR_SIZE =
    (uint32_t)sizeof(GAMEPAD_HID_REPORT_DESCRIPTOR);

#endif /* GAMEPAD_HID_DESCRIPTOR_H */
