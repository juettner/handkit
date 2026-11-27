#!/usr/bin/env python3
"""
picture_guides.py

The guides for the pictures P.S. keeps in a hand: a few ways to draw each
one, which the drawing page (HandEditor) shows beside the square. Tap one
and it lies pale in the square, to be traced over.

They are written out here as plain geometry (a rectangle, an arc, a spiral)
and turned into strokes like the ones in a hand file. Run it and it rewrites
the list in both places that have one, between their "guides: begin" and
"guides: end" lines:

    python3 Tools/picture_guides.py

    python3 Tools/picture_guides.py --sheet guides.png

The second also draws every guide on one sheet, to look at without building
the app (it needs Pillow: pip install pillow).

To add a way of drawing something, add a list of strokes to GUIDES below.
A stroke is a list of (x, y) points, y growing downward, in any unit: each
drawing is moved to start at 0, 0 and the page fits it to its box. The pen
rounds every point it passes (see Written.smooth), so a corner that should
stay a corner is written twice; `line` does that for you.
"""

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    (ROOT / "App/HandkitApp/Pictures.swift", "    "),
    (ROOT / "Demo/HandKitDemo/DemoApp.swift", "    "),
]
BEGIN = "// guides: begin"
END = "// guides: end"


# MARK: - Shapes

def line(*points, closed=False):
    """Straight lines from point to point. Every corner is kept a corner."""
    points = list(points)
    if closed:
        points.append(points[0])
    out = [points[0]]
    for point in points[1:-1]:
        out += [point, point]
    out.append(points[-1])
    return out


def rect(x0, y0, x1, y1):
    return line((x0, y0), (x1, y0), (x1, y1), (x0, y1), closed=True)


def arc(cx, cy, rx, ry, start, end, steps=None):
    """Part of an ellipse, in degrees. 0 is to the right, 90 is down, 270 is up."""
    steps = steps or max(4, int(abs(end - start) / 15))
    return [
        (cx + rx * math.cos(math.radians(start + (end - start) * i / steps)),
         cy + ry * math.sin(math.radians(start + (end - start) * i / steps)))
        for i in range(steps + 1)
    ]


def circle(cx, cy, r):
    return arc(cx, cy, r, r, 0, 360, 12)


def curve(*points, steps=6):
    """A smooth line through every point given (a Catmull-Rom spline)."""
    p = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(p) - 2):
        for step in range(steps):
            t = step / steps
            out.append(tuple(
                0.5 * (2 * p[i][k] + (p[i + 1][k] - p[i - 1][k]) * t
                       + (2 * p[i - 1][k] - 5 * p[i][k] + 4 * p[i + 1][k] - p[i + 2][k]) * t * t
                       + (3 * p[i][k] - p[i - 1][k] - 3 * p[i + 1][k] + p[i + 2][k]) * t ** 3)
                for k in (0, 1)))
    out.append(points[-1])
    return out


def join(*pieces):
    """Pieces drawn one after another without lifting the pen, a corner where they meet."""
    out = list(pieces[0])
    for piece in pieces[1:]:
        out.append(out[-1])
        out += list(piece)[1:] if piece[0] == out[-1] else list(piece)
    return out


def rounded(x0, y0, x1, y1, r):
    """A rectangle with round corners."""
    return (arc(x1 - r, y0 + r, r, r, 270, 360, 3) + arc(x1 - r, y1 - r, r, r, 0, 90, 3)
            + arc(x0 + r, y1 - r, r, r, 90, 180, 3) + arc(x0 + r, y0 + r, r, r, 180, 270, 3)
            + [(x1 - r, y0)])


def heart(cx, cy, width):
    """A heart, from its lower point round and back, centred on cx, cy."""
    def at(t):
        return (16 * math.sin(t) ** 3,
                -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)))
    scale = width / 32
    half = [at(math.pi + math.pi * i / 10) for i in range(11)]
    other = [at(2 * math.pi + math.pi * i / 10) for i in range(11)]
    return [(cx + x * scale, cy + (y + 2.5) * scale) for x, y in join(half, other)]


def teardrop(cx, bottom, width, height):
    """A flame: pointed at the top, round at the foot."""
    r = width / 2
    top = bottom - height
    left = curve((cx, top), (cx - r * 0.45, top + height * 0.3), (cx - r, bottom - r * 1.05))
    foot = arc(cx, bottom - r, r, r, 180, 0, 8)
    right = curve((cx + r, bottom - r * 1.05), (cx + r * 0.45, top + height * 0.3), (cx, top))
    return left + foot[1:-1] + right


def pin(cx, tip, r):
    """A map pin: a round head that comes down to a point at cx, tip."""
    head = arc(cx, tip - 2.1 * r, r, r, 140, 400, 10)
    return join([(cx, tip), head[0]], head, [head[-1], (cx, tip)])


def turned(strokes, degrees, cx=0.0, cy=0.0):
    """The strokes turned about cx, cy. A positive angle turns clockwise."""
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return [[(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in stroke]
            for stroke in strokes]


def scaled(stroke, factor, cx, cy):
    return [(cx + (x - cx) * factor, cy + (y - cy) * factor) for x, y in stroke]


# MARK: - The pictures

def envelope_sealed():
    body = rect(0, 0, 3.36, 2.16)
    flap = line((0, 0), (1.68, 1.28), (3.36, 0))
    plain = [body, flap]
    # The flap held down by a heart.
    hearted = [body, line((0, 0), (1.42, 1.08)), line((1.94, 1.08), (3.36, 0)), heart(1.68, 1.2, 0.8)]
    # A round flap, a wax seal and the two folds of the back.
    sealed = [
        body,
        curve((0, 0), (0.7, 0.75), (1.68, 1.25), (2.66, 0.75), (3.36, 0)),
        circle(1.68, 1.25, 0.27),
        line((0, 2.16), (1.1, 1.05)),
        line((3.36, 2.16), (2.26, 1.05)),
    ]
    return [plain, hearted, sealed]


def envelope_open():
    body = line((0, 1.36), (0, 3.28), (3.36, 3.28), (3.36, 1.36))
    flap = line((0, 1.36), (1.68, 0), (3.36, 1.36))
    front = line((0, 1.36), (1.68, 2.4), (3.36, 1.36))
    plain = [body, flap, front]
    # A letter half out of it, two lines written on it.
    letter = [
        body, front,
        line((0.5, 1.67), (0.5, 0.35), (2.86, 0.35), (2.86, 1.67)),
        line((0, 1.36), (0.5, 0.955)),
        line((1.248, 0.35), (1.68, 0), (2.112, 0.35)),
        line((2.86, 0.955), (3.36, 1.36)),
        line((0.95, 0.85), (2.41, 0.85)),
        line((0.95, 1.3), (2.41, 1.3)),
    ]
    # A heart leaving it.
    loved = [body, flap, front, heart(1.68, -0.75, 0.9)]
    return [plain, letter, loved]


def drawer():
    def knob(x, y):
        return circle(x, y, 0.16)
    chest = [
        rect(0, 0, 3.04, 2.56),
        line((0, 1.28), (3.04, 1.28)),
        knob(1.52, 0.64), knob(1.52, 1.92),
        line((0.24, 2.56), (0.24, 2.88)),
        line((2.8, 2.56), (2.8, 2.88)),
    ]
    # Three drawers, a bar to pull each by.
    tall = [
        rect(0, 0, 2.7, 3.0),
        line((0, 1.0), (2.7, 1.0)),
        line((0, 2.0), (2.7, 2.0)),
        line((1.0, 0.5), (1.7, 0.5)),
        line((1.0, 1.5), (1.7, 1.5)),
        line((1.0, 2.5), (1.7, 2.5)),
    ]
    # One drawer pulled open, an envelope standing in it.
    pulled = [
        rect(0, 1.3, 3.0, 2.7),
        curve((1.15, 1.9), (1.5, 2.1), (1.85, 1.9)),
        line((0, 1.3), (0.6, 0.6), (0.9, 0.6)),
        line((2.3, 0.6), (3.6, 0.6), (3.0, 1.3)),
        line((3.6, 0.6), (3.6, 2.0), (3.0, 2.7)),
        line((0.9, 1.3), (0.9, 0.0), (2.3, 0.0), (2.3, 1.3)),
        line((0.9, 0.0), (1.6, 0.55), (2.3, 0.0)),
    ]
    return [chest, tall, pulled]


def map_():
    sheet = line((0, 0.48), (1.12, 0), (2.24, 0.48), (3.36, 0), (3.36, 2.4), (2.24, 2.88), (1.12, 2.4), (0, 2.88), closed=True)
    folds = [line((1.12, 0), (1.12, 2.4)), line((2.24, 0.48), (2.24, 2.88))]
    trail = [line((0.4, 2.16), (0.64, 1.92)), line((0.88, 1.68), (1.28, 1.6)),
             line((1.52, 1.68), (1.84, 1.84)), line((2.08, 1.84), (2.4, 1.6))]
    cross = [line((2.56, 1.04), (2.96, 1.44)), line((2.96, 1.04), (2.56, 1.44))]
    marked = [sheet] + folds + trail + cross
    # The same map with a pin in it.
    pinned = [sheet] + folds + trail[:3] + [pin(2.8, 1.75, 0.34), circle(2.8, 1.04, 0.1)]
    # An old sheet, its edges uneven, a trail to a cross.
    top = curve((0, 0.2), (0.55, 0.0), (1.15, 0.25), (1.75, 0.05), (2.4, 0.25), (2.95, 0.05), (3.4, 0.2))
    bottom = curve((3.4, 2.6), (2.85, 2.8), (2.25, 2.55), (1.65, 2.8), (1.0, 2.55), (0.45, 2.8), (0, 2.6))
    old = [
        join(top, [(3.4, 0.2), (3.4, 2.6)], bottom, [(0, 2.6), (0, 0.2)]),
        line((0.5, 2.1), (0.75, 1.8)),
        line((0.95, 1.5), (1.3, 1.3)),
        line((1.6, 1.25), (1.95, 1.4)),
        line((2.2, 1.5), (2.5, 1.35)),
        line((2.65, 0.75), (3.05, 1.15)),
        line((3.05, 0.75), (2.65, 1.15)),
        line((0.45, 0.95), (0.75, 0.55), (1.05, 0.95)),
    ]
    return [marked, pinned, old]


def heart_halves(cx, cy, width):
    """The same heart in two strokes, each from the dip at the top down to the point."""
    whole = heart(cx, cy, width)
    # `heart` goes point, left side, dip (written twice: a corner), right side, point.
    dip = next(i for i in range(1, len(whole)) if whole[i] == whole[i - 1])
    return [list(reversed(whole[:dip])), whole[dip:]]


def hearts():
    plain = [heart(1.5, 1.3, 3.0)]
    # Two strokes, the way most people draw one: down the left, then down the right.
    halves = heart_halves(1.5, 1.3, 3.0)
    # Standing on the spot it marks: the same heart, drawn out to a long point, as a pin is.
    middle = 1.3 + 2.5 * 3.0 / 32
    pinned = [[(x, y if y < middle else middle + (y - middle) * 1.7) for x, y in heart(1.5, 1.3, 3.0)]]
    return [plain, halves, pinned]


def flashlight():
    side = [
        line((1.84, 0.48), (0, 0.48), (0, 1.28), (1.84, 1.28)),
        line((1.84, 0.48), (2.48, 0), (2.96, 0), (2.96, 1.76), (2.48, 1.76), (1.84, 1.28), (1.84, 0.48)),
        line((2.96, 0), (3.2, 0), (3.2, 1.76), (2.96, 1.76)),
        rect(0.64, 0.24, 1.2, 0.48),
    ]
    # Held up at a slant, its light going out ahead of it.
    rays = [line((3.5, 0.88), (4.25, 0.88)), line((3.45, 0.3), (4.1, -0.1)), line((3.45, 1.46), (4.1, 1.86))]
    lit = turned(side + rays, -38)
    # Standing on its end, shining upward.
    up = [
        line((0.45, 1.3), (0, 0.75), (0, 0.35), (1.6, 0.35), (1.6, 0.75), (1.15, 1.3)),
        line((0.45, 1.3), (0.45, 3.3), (1.15, 3.3), (1.15, 1.3), closed=True),
        rect(0.66, 1.75, 0.94, 2.3),
        line((0.45, 3.05), (1.15, 3.05)),
        line((0.8, 0.05), (0.8, -0.55)),
        line((0.3, 0.05), (0.0, -0.45)),
        line((1.3, 0.05), (1.6, -0.45)),
    ]
    return [side, lit, up]


def candle():
    pillar = [
        line((0, 0.64), (0, 3.12), (1.6, 3.12), (1.6, 0.64)),
        arc(0.8, 0.64, 0.8, 0.2, 180, 540, 12),
        curve((0.8, 0.64), (0.8, 0.32), (0.92, 0.0)),
        curve((0.32, 0.84), (0.32, 1.36), (0.44, 1.52), (0.56, 1.3), (0.56, 0.84)),
    ]
    # A candle in its dish, a ring to carry it by.
    carried = [
        line((0.75, 3.0), (0.75, 0.55), (1.55, 0.55), (1.55, 3.0)),
        curve((1.15, 0.55), (1.15, 0.25), (1.27, 0.0)),
        join([(0.0, 3.0), (2.3, 3.0)], curve((2.3, 3.0), (2.05, 3.4), (1.6, 3.5), (0.7, 3.5), (0.25, 3.4), (0.0, 3.0))),
        circle(2.58, 3.15, 0.28),
    ]
    # A short one, burnt down, the wax run over its side.
    melted = [
        join([(0, 0.9), (0, 3.0)], [(0, 3.0), (1.8, 3.0)], [(1.8, 3.0), (1.8, 0.9)]),
        curve((0, 0.9), (0.3, 0.75), (0.6, 0.95), (0.9, 0.8), (1.2, 0.95), (1.5, 0.75), (1.8, 0.9)),
        curve((0.9, 0.8), (0.9, 0.4), (1.02, 0.1)),
        curve((0.32, 0.8), (0.32, 1.65), (0.46, 1.85), (0.6, 1.65), (0.6, 0.95)),
        curve((1.25, 0.95), (1.25, 1.3), (1.37, 1.45), (1.48, 1.3), (1.48, 0.78)),
    ]
    return [pillar, carried, melted]


def candle_flame():
    plain = [teardrop(0.94, 3.52, 1.88, 3.52)]
    # Leaning, as in a draught.
    leaning = [curve(
        (1.25, 0.0), (0.75, 1.05), (0.2, 1.8), (0.05, 2.55), (0.3, 3.2), (0.9, 3.5),
        (1.45, 3.3), (1.8, 2.8), (1.82, 2.15), (1.55, 1.45), (1.3, 0.8), (1.25, 0.0),
    )]
    # With the paler flame inside it.
    inner = [teardrop(0.94, 3.52, 1.88, 3.52), teardrop(0.94, 3.3, 0.8, 1.5)]
    return [plain, leaning, inner]


def seashell():
    # A scallop: a fan of ribs over a small hinge.
    edge = [(0.04, 1.98)]
    for i in range(7):
        a0 = 180 + 180 * i / 7
        a1 = 180 + 180 * (i + 1) / 7
        mid = math.radians((a0 + a1) / 2)
        cx, cy = 2.31 + 1.95 * math.cos(mid), 2.0 + 1.75 * math.sin(mid)
        lump = arc(cx, cy, 0.5, 0.42, math.degrees(mid) - 100, math.degrees(mid) + 100, 6)
        edge = join(edge, lump) if i else lump
    scallop = [
        join([(1.91, 2.7), edge[0]], edge, [edge[-1], (2.71, 2.7)]),
        line((1.91, 2.7), (1.67, 2.7), (1.75, 3.1), (2.87, 3.1), (2.95, 2.7), (2.71, 2.7)),
    ] + [line((2.31 + 0.33 * math.cos(math.radians(a)), 2.55 + 0.25 * math.sin(math.radians(a))),
              (2.31 + 1.75 * math.cos(math.radians(a)), 2.0 + 1.6 * math.sin(math.radians(a))))
         for a in (205, 232, 258, 282, 308, 335)]

    # A nautilus: one line winding outward, and the walls of its chambers.
    grow = math.log(3.0) / (2 * math.pi)

    def spiral(turn):
        r = 0.16 * math.exp(grow * turn)
        return (r * math.cos(turn), r * math.sin(turn))
    winding = [spiral(math.pi + 4 * math.pi * i / 64) for i in range(65)]
    nautilus = [join(winding, curve(spiral(5 * math.pi), (-1.65, -0.22), spiral(3 * math.pi)))]
    for k in range(1, 7):
        turn = 3 * math.pi + k * 2 * math.pi / 7
        inner, outer = spiral(turn - 2 * math.pi), spiral(turn)
        bend = spiral(turn - 0.35)
        middle = ((inner[0] + outer[0]) / 2 * 0.4 + bend[0] * 0.6 * 0.66, (inner[1] + outer[1]) / 2 * 0.4 + bend[1] * 0.6 * 0.66)
        nautilus.append(curve(inner, middle, outer))

    # A spire: a long shell wound to a point, the kind found whole on a beach.
    rows = [0.0, 0.55, 1.15, 1.85, 2.65, 3.6]

    def half(y):
        return 0.27 * y
    left, right = [], []
    for top, bottom in zip(rows, rows[1:]):
        bulge = 0.1 + 0.03 * bottom
        l = curve((-half(top), top), (-(half(top) + half(bottom)) / 2 - bulge, (top + bottom) / 2 + 0.05), (-half(bottom), bottom))
        r = curve((half(top), top), ((half(top) + half(bottom)) / 2 + bulge, (top + bottom) / 2 + 0.05), (half(bottom), bottom))
        left = join(left, l) if left else l
        right = join(right, r) if right else r
    foot = curve((-half(3.6), 3.6), (-0.6, 4.2), (0.1, 4.45), (0.75, 4.15), (half(3.6), 3.6))
    spire = [join(list(reversed(right)), left, foot)]
    for y in rows[1:-1]:
        spire.append(curve((-half(y), y), (0, y + 0.12 + 0.05 * y), (half(y), y)))
    spire.append(arc(0.3, 3.85, 0.42, 0.26, 0, 360, 12))
    spire = turned(spire, 32)
    return [scallop, nautilus, spire]


def doodle():
    star = line(*[(1.5 + 1.5 * math.cos(math.radians(-90 + 144 * i)), 1.5 + 1.5 * math.sin(math.radians(-90 + 144 * i))) for i in range(5)], closed=True)
    flower = [circle(1.5, 1.3, 0.3)]
    for i in range(6):
        a = math.radians(60 * i - 90)
        petal = arc(1.5 + 0.78 * math.cos(a), 1.3 + 0.78 * math.sin(a), 0.48, 0.3, 0, 360, 12)
        flower.append(turned([petal], 60 * i - 90, 1.5 + 0.78 * math.cos(a), 1.3 + 0.78 * math.sin(a))[0])
    flower.append(curve((1.5, 2.6), (1.4, 3.3), (1.6, 4.0)))
    flower.append(curve((1.5, 3.4), (2.0, 2.95), (2.4, 3.1), (2.0, 3.45), (1.5, 3.4)))
    return [[heart(1.5, 1.3, 3.0)], [star], flower]


def status_signal():
    boxes = [rect(0.96 * i, 1.68 - 0.56 * i, 0.96 * i + 0.56, 2.24) for i in range(4)]
    boxes[0] = rect(0, 1.6, 0.56, 2.24)
    # Four plain lines: the fewest strokes, and the clearest this small.
    lines = [line((0.95 * i, 2.4), (0.95 * i, 1.8 - 0.6 * i)) for i in range(4)]
    # A mast and what it sends.
    mast = [
        line((1.25, 2.4), (1.8, 0.85), (2.35, 2.4)),
        circle(1.8, 0.7, 0.14),
        arc(1.8, 0.7, 0.6, 0.6, 130, 230), arc(1.8, 0.7, 1.15, 1.15, 135, 225),
        arc(1.8, 0.7, 0.6, 0.6, -50, 50), arc(1.8, 0.7, 1.15, 1.15, -45, 45),
    ]
    return [boxes, lines, mast]


def status_wifi():
    arcs = [
        arc(1.9, 2.55, 2.6, 2.6, 223, 317, 8),
        arc(1.9, 2.55, 1.75, 1.75, 225, 315, 7),
        arc(1.9, 2.55, 0.9, 0.9, 228, 312, 5),
        circle(1.9, 2.4, 0.16),
    ]
    # A fan: the outside drawn in one line, two arcs inside it.
    sweep = arc(1.9, 2.6, 2.6, 2.6, 225, 315, 8)
    fan = [
        join([(1.9, 2.6), sweep[0]], sweep, [sweep[-1], (1.9, 2.6)]),
        arc(1.9, 2.6, 1.75, 1.75, 225, 315, 7),
        arc(1.9, 2.6, 0.9, 0.9, 225, 315, 5),
    ]
    # Three roofs and a dot, for a hand that will not draw an arc this small.
    roofs = [
        line((0, 0.95), (1.9, 0), (3.8, 0.95)),
        line((0.65, 1.5), (1.9, 0.85), (3.15, 1.5)),
        line((1.3, 2.0), (1.9, 1.7), (2.5, 2.0)),
        circle(1.9, 2.45, 0.14),
    ]
    return [arcs, fan, roofs]


def status_battery():
    filled = [rect(0, 0, 3.2, 1.76), line((3.52, 0.56), (3.52, 1.2)), rect(0.32, 0.32, 2.24, 1.44)]
    # Round at the corners, three bars of charge.
    bars = [
        rounded(0, 0, 3.2, 1.76, 0.35),
        line((3.2, 0.56), (3.5, 0.56), (3.5, 1.2), (3.2, 1.2)),
        line((0.75, 0.45), (0.75, 1.31)),
        line((1.4, 0.45), (1.4, 1.31)),
        line((2.05, 0.45), (2.05, 1.31)),
    ]
    # Charging.
    bolt = [
        rect(0, 0, 3.2, 1.76),
        line((3.52, 0.56), (3.52, 1.2)),
        line((1.9, 0.22), (1.15, 0.98), (1.7, 0.98), (1.3, 1.54), (2.05, 0.78), (1.5, 0.78), closed=True),
    ]
    return [filled, bars, bolt]


GUIDES = [
    ("envelope-sealed", envelope_sealed),
    ("envelope-open", envelope_open),
    ("drawer", drawer),
    ("map", map_),
    ("heart", hearts),
    ("flashlight", flashlight),
    ("candle", candle),
    ("candle-flame", candle_flame),
    ("seashell", seashell),
    ("doodle", doodle),
    ("status-signal", status_signal),
    ("status-wifi", status_wifi),
    ("status-battery", status_battery),
]


# MARK: - Writing them out

def settled(strokes):
    """The drawing moved to start at 0, 0, its numbers rounded, and how wide it is."""
    xs = [x for stroke in strokes for x, _ in stroke]
    ys = [y for stroke in strokes for _, y in stroke]
    left, top = min(xs), min(ys)
    moved = [[(round(x - left, 2), round(y - top, 2)) for x, y in stroke] for stroke in strokes]
    return moved, round(max(xs) - left, 2)


def swift(indent):
    out = []
    for name, make in GUIDES:
        out.append(f'{indent}    "{name}": [')
        for strokes in make():
            moved, width = settled(strokes)
            out.append(f"{indent}        Glyph(strokes: [")
            for stroke in moved:
                numbers = ", ".join(f"{value:g}" for point in stroke for value in point)
                out.append(f"{indent}            [{numbers}],")
            out.append(f"{indent}        ], advance: {width:g}),")
        out.append(f"{indent}    ],")
    return out


def rewrite(path, indent):
    lines = path.read_text().split("\n")
    begin = next(i for i, text in enumerate(lines) if BEGIN in text)
    end = next(i for i, text in enumerate(lines) if END in text)
    path.write_text("\n".join(lines[:begin + 1] + swift(indent) + lines[end:]))


def smooth(points, steps=8):
    """Written.smooth, as points: through the midpoints, the points as the pull."""
    if len(points) < 3:
        return list(points)
    out = [points[0]]
    here = points[0]
    for i in range(1, len(points) - 1):
        mid = ((points[i][0] + points[i + 1][0]) / 2, (points[i][1] + points[i + 1][1]) / 2)
        for step in range(1, steps + 1):
            t = step / steps
            out.append(tuple((1 - t) ** 2 * here[k] + 2 * (1 - t) * t * points[i][k] + t * t * mid[k] for k in (0, 1)))
        here = mid
    out.append(points[-1])
    return out


def sheet(path):
    """Every guide on one picture, each as the page shows it: pale in a square."""
    from PIL import Image, ImageDraw
    side, gap, top = 300, 30, 40
    image = Image.new("RGB", (gap + 3 * (side + gap), top + len(GUIDES) * (side + gap + 20)), "white")
    draw = ImageDraw.Draw(image)
    for row, (name, make) in enumerate(GUIDES):
        y0 = top + row * (side + gap + 20)
        draw.text((gap, y0 - 16), name, fill=(107, 98, 90))
        for column, strokes in enumerate(make()):
            x0 = gap + column * (side + gap)
            draw.rectangle([x0, y0, x0 + side, y0 + side], outline=(230, 225, 218))
            moved, width = settled(strokes)
            height = max(y for stroke in moved for _, y in stroke)
            box = side * 0.7
            scale = min(box / max(width, 0.01), box / max(height, 0.01)) * 0.92
            dx = x0 + (side - width * scale) / 2
            dy = y0 + (side - height * scale) / 2
            for stroke in moved:
                points = [(dx + x * scale, dy + y * scale) for x, y in smooth(stroke)]
                if len(points) > 1:
                    draw.line(points, fill=(150, 142, 134), width=4, joint="curve")
    image.save(path)


if __name__ == "__main__":
    for file, indent in FILES:
        rewrite(file, indent)
    if "--sheet" in sys.argv:
        sheet(sys.argv[sys.argv.index("--sheet") + 1])
