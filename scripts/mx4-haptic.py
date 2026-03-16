#!/usr/bin/env python3
"""Send haptic feedback to Logitech MX Master 4 via HID++ 2.0.

Native Linux implementation — no Logi Options+ or HapticWebPlugin required.
Sends HID++ commands directly to the Bolt receiver via /dev/hidraw.
Zero external dependencies, only Python 3 standard library.

Based on https://github.com/MyrikLD/mx4hyprland/blob/main/mx_master_4.py
"""

import os
import select
import sys
from struct import pack

LOGITECH_BOLT_VID = "046D"
LOGITECH_BOLT_PID = "C548"
REPORT_SHORT = 0x10
REPORT_LONG = 0x11
DEVICE_INDEX = 0x02  # MX Master 4 on Bolt receiver
HAPTIC_FEATURE_ID = 0x19B0
HAPTIC_FUNC_SWID = (4 << 4) | 0x0E  # function 4, swId 0xE

WAVEFORMS = {
    "sharp_state_change": 0,
    "damp_state_change": 1,
    "sharp_collision": 2,
    "damp_collision": 3,
    "subtle_collision": 4,
    "happy_alert": 5,
    "angry_alert": 6,
    "completed": 7,
    "square": 8,
    "wave": 9,
    "firework": 10,
    "mad": 11,
    "knock": 12,
    "jingle": 13,
    "ringing": 14,
}


def find_hidraw():
    """Find the HID++ hidraw device (supports Report ID 0x11)."""
    for entry in sorted(os.listdir("/sys/class/hidraw")):
        try:
            with open(f"/sys/class/hidraw/{entry}/device/uevent") as f:
                content = f.read().upper()
            if LOGITECH_BOLT_VID not in content or LOGITECH_BOLT_PID not in content:
                continue
            with open(f"/sys/class/hidraw/{entry}/device/report_descriptor", "rb") as f:
                desc = f.read()
            # Find Report ID 0x11 (long HID++) in descriptor
            if any(desc[i] == 0x85 and desc[i + 1] == REPORT_LONG for i in range(len(desc) - 1)):
                return f"/dev/{entry}"
        except (FileNotFoundError, PermissionError):
            continue
    return None


def hidpp_request(fd, feat_func, *args):
    """Send short HID++ request, return response bytes."""
    data = bytes(args)
    if len(data) < 3:
        data += b"\x00" * (3 - len(data))
    packet = pack(">BBH3s", REPORT_SHORT, DEVICE_INDEX, feat_func, data)
    fd.write(packet)

    for _ in range(10):
        ready, _, _ = select.select([fd], [], [], 2.0)
        if not ready:
            return None
        resp = fd.read(20)
        if resp and resp[1] == DEVICE_INDEX:
            return resp
    return None


def main():
    debug = "--debug" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--debug"]
    waveform_name = args[0] if args else "knock"

    if waveform_name == "--list":
        for name, wid in WAVEFORMS.items():
            print(f"{name} ({wid})")
        return

    if waveform_name not in WAVEFORMS:
        print(f"Unknown waveform: {waveform_name}", file=sys.stderr)
        print(f"Available: {', '.join(WAVEFORMS.keys())}", file=sys.stderr)
        sys.exit(1)

    dev_path = find_hidraw()
    if not dev_path:
        print("Logitech Bolt receiver (HID++) not found", file=sys.stderr)
        sys.exit(1)

    if debug:
        print(f"Device: {dev_path}")

    with open(dev_path, "rb+", buffering=0) as fd:
        # Resolve HAPTIC feature index via IRoot
        hi, lo = (HAPTIC_FEATURE_ID >> 8) & 0xFF, HAPTIC_FEATURE_ID & 0xFF
        resp = hidpp_request(fd, 0x0000, hi, lo, 0)
        if not resp or len(resp) < 5:
            print("Could not resolve HAPTIC feature", file=sys.stderr)
            sys.exit(1)
        feat_idx = resp[4]

        if debug:
            print(f"HAPTIC feature index: 0x{feat_idx:02X}")

        # Trigger waveform
        combined = (feat_idx << 8) | HAPTIC_FUNC_SWID
        waveform_id = WAVEFORMS[waveform_name]
        hidpp_request(fd, combined, waveform_id)

        if debug:
            print(f"Sent: {waveform_name} ({waveform_id})")


if __name__ == "__main__":
    main()
