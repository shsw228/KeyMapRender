#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Minimal Vial/VIA HID bridge.
Compatible with the same 32-byte message framing used by vial-gui.
Requires `hid` (hidapi python binding).
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import time
from typing import Any, Dict, List, Tuple

MSG_LEN = 32
RETRIES = 20
READ_TIMEOUT_MS = 500
BUFFER_FETCH_CHUNK = 28

CMD_VIA_GET_PROTOCOL_VERSION = 0x01
CMD_VIA_GET_LAYER_COUNT = 0x11
CMD_VIA_KEYMAP_GET_BUFFER = 0x12
CMD_VIA_GET_KEYCODE = 0x04


def fail(message: str, logs: List[str] | None = None, extra: Dict[str, Any] | None = None) -> None:
    payload: Dict[str, Any] = {"ok": False, "error": message}
    if logs:
        payload["logs"] = logs
    if extra:
        payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(1)


def hid_send(dev, msg: bytes, retries: int = RETRIES) -> bytes:
    if len(msg) > MSG_LEN:
        raise RuntimeError("message must be <= 32 bytes")
    msg = msg + (b"\x00" * (MSG_LEN - len(msg)))

    first = True
    data = b""
    while retries > 0:
        retries -= 1
        if not first:
            time.sleep(0.05)
        first = False
        try:
            # hidapi expects report-id-prefixed payload
            written = dev.write(b"\x00" + msg)
            if written != MSG_LEN + 1:
                continue
            data = bytes(dev.read(MSG_LEN, timeout_ms=READ_TIMEOUT_MS))
            if not data:
                continue
        except OSError:
            continue
        break

    if not data:
        raise RuntimeError("failed to communicate with the device")
    return data


def find_rawhid_device(vid: int, pid: int) -> Tuple[Dict[str, Any], List[str]]:
    logs: List[str] = []
    candidates: List[Dict[str, Any]] = []

    for dev in hid.enumerate():
        if dev.get("vendor_id") != vid or dev.get("product_id") != pid:
            continue
        up = int(dev.get("usage_page", 0) or 0)
        us = int(dev.get("usage", 0) or 0)
        path = dev.get("path")
        logs.append(f"seen path={path} usage_page=0x{up:04X} usage=0x{us:02X}")
        if up == 0xFF60 and us == 0x61:
            candidates.append(dev)

    if not candidates:
        raise RuntimeError("rawhid interface (usage_page=0xFF60 usage=0x61) not found")

    # stable-ish pick
    candidates.sort(key=lambda d: str(d.get("path", "")))
    return candidates[0], logs


def probe(vid: int, pid: int) -> None:
    try:
        desc, logs = find_rawhid_device(vid, pid)
    except Exception as exc:
        fail(str(exc))

    dev = hid.device()
    try:
        dev.open_path(desc["path"])
    except OSError as exc:
        fail(f"open_path failed: {exc}", logs)

    try:
        proto_data = hid_send(dev, struct.pack("B", CMD_VIA_GET_PROTOCOL_VERSION))
        layer_data = hid_send(dev, struct.pack("B", CMD_VIA_GET_LAYER_COUNT))
        key_data = hid_send(dev, struct.pack("BBBB", CMD_VIA_GET_KEYCODE, 0, 0, 0))

        proto = struct.unpack(">H", proto_data[1:3])[0]
        layers = layer_data[1]
        keycode = struct.unpack(">H", key_data[4:6])[0]

        print(
            json.dumps(
                {
                    "ok": True,
                    "mode": "probe",
                    "protocol_version": f"0x{proto:04X}",
                    "layer_count": int(layers),
                    "keycode_l0_r0_c0": int(keycode),
                    "path": str(desc.get("path")),
                    "logs": logs,
                },
                ensure_ascii=False,
            )
        )
    except Exception as exc:
        fail(str(exc), logs, {"path": str(desc.get("path"))})
    finally:
        dev.close()


def dump_keymap(vid: int, pid: int, rows: int, cols: int) -> None:
    if rows <= 0 or cols <= 0:
        fail("rows/cols must be positive integers")

    try:
        desc, logs = find_rawhid_device(vid, pid)
    except Exception as exc:
        fail(str(exc))

    dev = hid.device()
    try:
        dev.open_path(desc["path"])
    except OSError as exc:
        fail(f"open_path failed: {exc}", logs)

    try:
        proto_data = hid_send(dev, struct.pack("B", CMD_VIA_GET_PROTOCOL_VERSION))
        layer_data = hid_send(dev, struct.pack("B", CMD_VIA_GET_LAYER_COUNT))
        proto = struct.unpack(">H", proto_data[1:3])[0]
        layers = int(layer_data[1])

        total_size = layers * rows * cols * 2
        keymap_raw = b""
        for offset in range(0, total_size, BUFFER_FETCH_CHUNK):
            size = min(total_size - offset, BUFFER_FETCH_CHUNK)
            data = hid_send(dev, struct.pack(">BHB", CMD_VIA_KEYMAP_GET_BUFFER, offset, size))
            keymap_raw += data[4 : 4 + size]

        keycodes: List[List[List[int]]] = [
            [[0 for _ in range(cols)] for _ in range(rows)] for _ in range(layers)
        ]
        for layer in range(layers):
            for row in range(rows):
                for col in range(cols):
                    base = ((layer * rows * cols) + (row * cols) + col) * 2
                    keycodes[layer][row][col] = struct.unpack(">H", keymap_raw[base : base + 2])[0]

        print(
            json.dumps(
                {
                    "ok": True,
                    "mode": "dump",
                    "protocol_version": f"0x{proto:04X}",
                    "layer_count": layers,
                    "matrix_rows": rows,
                    "matrix_cols": cols,
                    "keycodes": keycodes,
                    "path": str(desc.get("path")),
                    "logs": logs,
                },
                ensure_ascii=False,
            )
        )
    except Exception as exc:
        fail(str(exc), logs, {"path": str(desc.get("path"))})
    finally:
        dev.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)

    probe_cmd = sub.add_parser("probe")
    probe_cmd.add_argument("--vid", type=lambda s: int(s, 0), required=True)
    probe_cmd.add_argument("--pid", type=lambda s: int(s, 0), required=True)

    dump_cmd = sub.add_parser("dump")
    dump_cmd.add_argument("--vid", type=lambda s: int(s, 0), required=True)
    dump_cmd.add_argument("--pid", type=lambda s: int(s, 0), required=True)
    dump_cmd.add_argument("--rows", type=int, required=True)
    dump_cmd.add_argument("--cols", type=int, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    try:
        import hid  # type: ignore
    except Exception as exc:
        fail(f"python hid module is not available: {exc}")

    args = parse_args()
    if args.mode == "probe":
        probe(args.vid, args.pid)
    elif args.mode == "dump":
        dump_keymap(args.vid, args.pid, args.rows, args.cols)
