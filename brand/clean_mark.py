#!/usr/bin/env python3
"""Remove isolated alpha specks from the generated transparent mark."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: clean_mark.py <input.png> <output.png>", file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    img = Image.open(src).convert("RGBA")
    width, height = img.size
    alpha = img.getchannel("A")
    alpha_px = alpha.load()
    seen = bytearray(width * height)
    keep = bytearray(width * height)

    threshold = 3
    min_component_area = 100

    for y in range(height):
        for x in range(width):
            idx = y * width + x
            if seen[idx] or alpha_px[x, y] <= threshold:
                continue

            stack = [(x, y)]
            seen[idx] = 1
            coords: list[tuple[int, int]] = []

            while stack:
                cx, cy = stack.pop()
                coords.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    next_idx = ny * width + nx
                    if not seen[next_idx] and alpha_px[nx, ny] > threshold:
                        seen[next_idx] = 1
                        stack.append((nx, ny))

            if len(coords) >= min_component_area:
                for cx, cy in coords:
                    keep[cy * width + cx] = 1

    for _ in range(2):
        expanded = bytearray(keep)
        for y in range(height):
            for x in range(width):
                if not keep[y * width + x]:
                    continue
                for nx in (x - 1, x, x + 1):
                    for ny in (y - 1, y, y + 1):
                        if 0 <= nx < width and 0 <= ny < height:
                            expanded[ny * width + nx] = 1
        keep = expanded

    px = img.load()
    for y in range(height):
        for x in range(width):
            if keep[y * width + x]:
                continue
            r, g, b, _ = px[x, y]
            px[x, y] = (r, g, b, 0)

    img.save(dst)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
