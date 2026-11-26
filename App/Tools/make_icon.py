#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""
make_icon.py: the app's icon, until somebody draws a better one.

The drawing page's ruled square with one letter on it: an "h", written in one
stroke the way the pen writes. 1024 by 1024, corners left square (iOS cuts
them), written over the icon in the asset catalog.

    python3 App/Tools/make_icon.py
    uv run App/Tools/make_icon.py          the same, installing Pillow for the run

To use a drawing of your own instead: turn on "developer tools" on the app's
Keep page, draw the "app icon" entry on the drawing page, and "send the icon"
gives you icon.png to put in App/HandkitApp/Assets.xcassets/AppIcon.appiconset.
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "HandkitApp" / "Assets.xcassets" / "AppIcon.appiconset" / "icon.png"

SIDE = 1024
# Drawn four times too large and shrunk, which is what smooths the edges.
OVER = 4

PAPER = (255, 255, 255)
INK = (30, 26, 23)
GREY = (154, 144, 136)
FAINT = (196, 188, 178)
RULE = (232, 227, 220)

# The ruled lines, as shares of the side, moved a little from the drawing
# page's own so the letter sits in the middle of the icon.
TALL, MIDDLE, BASE, TAIL = 0.215, 0.445, 0.705, 0.86

# The "h": points the pen passes through, as shares of the side. Up the stem
# from the line is left out: the pen comes down it, back up over the arch,
# down again and flicks away.
LETTER = [
    (0.365, 0.185), (0.372, 0.33), (0.37, 0.50), (0.362, 0.70),
    (0.372, 0.60), (0.41, 0.505), (0.47, 0.452), (0.535, 0.455),
    (0.578, 0.51), (0.592, 0.60), (0.602, 0.668), (0.632, 0.70), (0.672, 0.688), (0.715, 0.64),
]


def smooth(points, steps=24):
    """The pen's own curve (Written.smooth): through the midpoints, pulled by the points."""
    out = [points[0]]
    start = points[0]
    for i in range(1, len(points) - 1):
        control = points[i]
        end = ((points[i][0] + points[i + 1][0]) / 2, (points[i][1] + points[i + 1][1]) / 2)
        for step in range(1, steps + 1):
            t = step / steps
            out.append((
                (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * control[0] + t ** 2 * end[0],
                (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * control[1] + t ** 2 * end[1],
            ))
        start = end
    # The last stretch is a straight line to the last point.
    for step in range(1, steps + 1):
        t = step / steps
        out.append((start[0] + (points[-1][0] - start[0]) * t, start[1] + (points[-1][1] - start[1]) * t))
    return out


def main():
    side = SIDE * OVER
    image = Image.new("RGB", (side, side), PAPER)
    draw = ImageDraw.Draw(image)

    def line(y, color, dash=None, width=5):
        y = round(y * side)
        thick = width * OVER
        if dash is None:
            draw.line([(0, y), (side, y)], fill=color, width=thick)
            return
        on, off = (round(part * OVER) for part in dash)
        x = round(off / 2)
        while x < side:
            draw.line([(x, y), (min(side, x + on), y)], fill=color, width=thick)
            x += on + off

    line(TALL, RULE)
    line(MIDDLE, FAINT, dash=(26, 34))
    line(BASE, GREY, width=6)
    line(TAIL, RULE)

    # A round nib: a filled circle at every step along the curve.
    nib = 0.058 * side / 2
    for x, y in smooth(LETTER, steps=160):
        draw.ellipse([x * side - nib, y * side - nib, x * side + nib, y * side + nib], fill=INK)

    image.resize((SIDE, SIDE), Image.LANCZOS).save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
