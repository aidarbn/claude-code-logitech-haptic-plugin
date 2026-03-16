#!/usr/bin/env python3
"""Send haptic feedback to Logitech MX Master 4 via HID++ 2.0.

Supports both Bolt USB receiver and Bluetooth connections.
Uses raw /dev/hidraw — no external dependencies required.
Based on https://github.com/MyrikLD/mx4hyprland/blob/main/mx_master_4.py
"""

import os
import select
import sys
from struct import pack

REPORT_SHORT = 0x10
REPORT_LONG = 0x11
HAPTIC_FEATURE_ID = 0x19B0
HAPTIC_FUNC_SWID = (4 << 4) | 0x0E  # function 4, swId 0xE

# Connection profiles: (VID, PID, device_index, use_long_reports)
CONNECTIONS = {
    "bolt": ("046D", "C548", 0x02, False),  # Bolt USB receiver
    "bt": ("046D", "B042", 0xFF, True),     # Bluetooth direct
}

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
    """Find the MX Master 4 hidraw device. Returns (path, device_index, use_long)."""
    for entry in sorted(os.listdir("/sys/class/hidraw")):
        try:
            with open(f"/sys/class/hidraw/{entry}/device/uevent") as f:
                content = f.read().upper()

            for conn_name, (vid, pid, dev_idx, use_long) in CONNECTIONS.items():
                if vid not in content or pid not in content:
                    continue

                # Check for Report ID 0x11 (long HID++) in descriptor
                with open(f"/sys/class/hidraw/{entry}/device/report_descriptor", "rb") as f:
                    desc = f.read()
                if not any(desc[i] == 0x85 and desc[i + 1] == REPORT_LONG for i in range(len(desc) - 1)):
                    continue

                dev_path = f"/dev/{entry}"
                try:
                    with open(dev_path, "rb+", buffering=0):
                        pass
                except (PermissionError, OSError):
                    continue
                return dev_path, dev_idx, use_long, conn_name

        except (FileNotFoundError, PermissionError):
            continue
    return None, None, None, None


def hidpp_request(fd, device_index, use_long, feat_func, *args):
    """Send HID++ request, return response bytes."""
    data = bytes(args)
    if use_long:
        if len(data) < 16:
            data += b"\x00" * (16 - len(data))
        feat_idx = (feat_func >> 8) & 0xFF
        func_swid = feat_func & 0xFF
        packet = pack(">BBBB16s", REPORT_LONG, device_index, feat_idx, func_swid, data)
    else:
        if len(data) < 3:
            data += b"\x00" * (3 - len(data))
        packet = pack(">BBH3s", REPORT_SHORT, device_index, feat_func, data)
    fd.write(packet)

    for _ in range(30):
        ready, _, _ = select.select([fd], [], [], 2.0)
        if not ready:
            return None
        resp = fd.read(20)
        if resp and resp[0] in (REPORT_SHORT, REPORT_LONG) and resp[1] == device_index:
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

    dev_path, dev_idx, use_long, conn_name = find_hidraw()
    if not dev_path:
        print("MX Master 4 not found (tried Bolt and Bluetooth)", file=sys.stderr)
        sys.exit(1)

    if debug:
        print(f"Device: {dev_path} ({conn_name})")
        print(f"Device index: 0x{dev_idx:02X}, long reports: {use_long}")

    with open(dev_path, "rb+", buffering=0) as fd:
        # Resolve HAPTIC feature index via IRoot
        hi, lo = (HAPTIC_FEATURE_ID >> 8) & 0xFF, HAPTIC_FEATURE_ID & 0xFF
        resp = hidpp_request(fd, dev_idx, use_long, 0x0000, hi, lo, 0)
        if not resp or len(resp) < 5:
            print("Could not resolve HAPTIC feature", file=sys.stderr)
            sys.exit(1)
        feat_idx = resp[4]

        if debug:
            print(f"HAPTIC feature index: 0x{feat_idx:02X}")

        # Trigger waveform
        combined = (feat_idx << 8) | HAPTIC_FUNC_SWID
        waveform_id = WAVEFORMS[waveform_name]
        hidpp_request(fd, dev_idx, use_long, combined, waveform_id)

        if debug:
            print(f"Sent: {waveform_name} ({waveform_id})")


if __name__ == "__main__":
    main()
