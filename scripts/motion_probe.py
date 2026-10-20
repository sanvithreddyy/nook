"""Measure the island's bottom edge and width per frame in a tour recording.

Usage: python3 scripts/motion_probe.py build/tour/tour.mov <start_s> <seconds>
Prints one row per frame: time, bottom edge (pt), width at 6 pt above the edge (pt), and
flags frames identical to the previous one while the island is moving (a dropped frame).
"""
import subprocess
import sys

import numpy as np

path, start, length = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                        "stream=width,height", "-of", "csv=p=0", path], capture_output=True, text=True)
w, h = map(int, probe.stdout.strip().split(","))
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", str(start), "-t", str(length), "-i", path,
                      "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
frames = np.frombuffer(raw, dtype=np.uint8).reshape(-1, h, w)
center = w // 2
prev_bottom = None
prev = None
for i, f in enumerate(frames):
    column = f[:, center - 40:center + 40].max(axis=1)
    black = column <= 3
    bottom = 0
    while bottom < h and black[bottom]:
        bottom += 1
    row = f[max(bottom - 12, 0)]
    xs = np.where(row <= 3)[0]
    width = 0
    if len(xs):
        # contiguous black run through the center
        left = center
        while left > 0 and row[left - 1] <= 3:
            left -= 1
        right = center
        while right < w - 1 and row[right + 1] <= 3:
            right += 1
        width = right - left + 1
    moving = prev_bottom is not None and bottom != prev_bottom
    stalled = prev is not None and np.array_equal(f, prev) and prev_bottom is not None
    print(f"{i / 60:6.3f}s bottom={bottom / 2:6.1f}pt width={width / 2:6.1f}pt{'  SAME' if stalled else ''}")
    prev_bottom = bottom
    prev = f
