#!/usr/bin/env python3
"""Generate Resources/AppIcon.icns — Graphite server + status-dot icon.

Draws a 1024 PNG with the standard library, then uses sips + iconutil.
Intermediate PNG/iconset files are written to a temp directory and discarded.
"""

from __future__ import annotations

import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

SIZE = 1024

BG = (0x1C, 0x1C, 0x1E, 255)
CARD = (0x2C, 0x2C, 0x2E, 255)
SLOT = (0x3A, 0x3A, 0x3C, 255)
TEXT = (0xF5, 0xF5, 0xF7, 255)
GREEN = (0x30, 0xD1, 0x58, 255)
BLUE = (0x64, 0xD2, 0xFF, 255)
DIM = (0x8E, 0x8E, 0x93, 255)


def write_png(path: str, width: int, height: int, rgba: bytearray) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(chunk(b"IEND", b""))


def blend(px: bytearray, size: int, x: int, y: int, color: tuple[int, int, int, int], cover: float) -> None:
    if cover <= 0 or x < 0 or y < 0 or x >= size or y >= size:
        return
    alpha = color[3] / 255.0 * min(1.0, cover)
    if alpha <= 0:
        return
    i = (y * size + x) * 4
    inv = 1.0 - alpha
    px[i] = int(px[i] * inv + color[0] * alpha)
    px[i + 1] = int(px[i + 1] * inv + color[1] * alpha)
    px[i + 2] = int(px[i + 2] * inv + color[2] * alpha)
    px[i + 3] = 255


def sd_round_box(px: float, py: float, cx: float, cy: float, hw: float, hh: float, radius: float) -> float:
    dx = abs(px - cx) - (hw - radius)
    dy = abs(py - cy) - (hh - radius)
    ox = max(dx, 0.0)
    oy = max(dy, 0.0)
    inside = min(max(dx, dy), 0.0)
    return math.hypot(ox, oy) + inside - radius


def fill_round_rect(
    px: bytearray,
    size: int,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    hw = (x1 - x0) * 0.5
    hh = (y1 - y0) * 0.5
    pad = 2
    xmin = max(0, int(x0 - pad))
    xmax = min(size, int(x1 + pad) + 1)
    ymin = max(0, int(y0 - pad))
    ymax = min(size, int(y1 + pad) + 1)
    for y in range(ymin, ymax):
        for x in range(xmin, xmax):
            dist = sd_round_box(x + 0.5, y + 0.5, cx, cy, hw, hh, radius)
            blend(px, size, x, y, color, 0.5 - dist)


def fill_circle(
    px: bytearray,
    size: int,
    cx: float,
    cy: float,
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    pad = 2
    xmin = max(0, int(cx - radius - pad))
    xmax = min(size, int(cx + radius + pad) + 1)
    ymin = max(0, int(cy - radius - pad))
    ymax = min(size, int(cy + radius + pad) + 1)
    for y in range(ymin, ymax):
        for x in range(xmin, xmax):
            dist = math.hypot(x + 0.5 - cx, y + 0.5 - cy) - radius
            blend(px, size, x, y, color, 0.5 - dist)


def fill_rect(
    px: bytearray,
    size: int,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    color: tuple[int, int, int, int],
) -> None:
    fill_round_rect(px, size, x0, y0, x1, y1, 0.0, color)


def draw_icon(size: int = SIZE) -> bytearray:
    px = bytearray([0, 0, 0, 255] * (size * size))
    fill_rect(px, size, 0, 0, size, size, BG)

    # Outer rounded plate so the silhouette reads as a Graphite tile.
    inset = size * 0.07
    fill_round_rect(px, size, inset, inset, size - inset, size - inset, size * 0.18, CARD)

    # Server chassis
    chassis_x0 = size * 0.22
    chassis_x1 = size * 0.78
    chassis_y0 = size * 0.24
    chassis_y1 = size * 0.78
    fill_round_rect(px, size, chassis_x0, chassis_y0, chassis_x1, chassis_y1, size * 0.06, SLOT)

    inner_x0 = chassis_x0 + size * 0.035
    inner_x1 = chassis_x1 - size * 0.035
    inner_y0 = chassis_y0 + size * 0.04
    inner_y1 = chassis_y1 - size * 0.04
    fill_round_rect(px, size, inner_x0, inner_y0, inner_x1, inner_y1, size * 0.045, CARD)

    # Three drive bays with status LEDs
    bay_colors = (GREEN, GREEN, BLUE)
    bay_top = inner_y0 + size * 0.06
    bay_height = size * 0.11
    bay_gap = size * 0.055
    led_r = size * 0.022
    for index, led in enumerate(bay_colors):
        y0 = bay_top + index * (bay_height + bay_gap)
        y1 = y0 + bay_height
        fill_round_rect(px, size, inner_x0 + size * 0.05, y0, inner_x1 - size * 0.05, y1, size * 0.028, SLOT)
        fill_circle(px, size, inner_x0 + size * 0.11, (y0 + y1) * 0.5, led_r, led)
        # Drive-window bars
        bar_x0 = inner_x0 + size * 0.18
        bar_x1 = inner_x1 - size * 0.10
        bar_y = (y0 + y1) * 0.5
        fill_round_rect(
            px,
            size,
            bar_x0,
            bar_y - size * 0.012,
            bar_x1,
            bar_y + size * 0.012,
            size * 0.01,
            DIM,
        )

    # Status badge in the top-right of the plate
    fill_circle(px, size, size * 0.78, size * 0.24, size * 0.055, GREEN)
    fill_circle(px, size, size * 0.78, size * 0.24, size * 0.028, TEXT)
    return px


def build_icns(output: str) -> None:
    os.makedirs(os.path.dirname(output), exist_ok=True)
    px = draw_icon(SIZE)
    with tempfile.TemporaryDirectory(prefix="ohmyservers-icon-") as tmp:
        master = os.path.join(tmp, "master.png")
        write_png(master, SIZE, SIZE, px)
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        specs = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for name, dim in specs:
            dest = os.path.join(iconset, name)
            subprocess.run(
                ["sips", "-z", str(dim), str(dim), master, "--out", dest],
                check=True,
                capture_output=True,
            )
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", output], check=True)
    if not os.path.isfile(output) or os.path.getsize(output) < 1024:
        raise SystemExit(f"icns was not created or is too small: {output}")


def main() -> int:
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    output = os.path.join(root, "Resources", "AppIcon.icns")
    build_icns(output)
    print(f"Wrote {output} ({os.path.getsize(output)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
