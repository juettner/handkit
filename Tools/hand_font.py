#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["fonttools>=4.40", "shapely>=2.0"]
# ///
"""
hand_font.py: the hand, as a font file.

The pen (Sources/HandKit/Handwriting.swift) writes lines from the strokes in
a hand.json. A Text, a label or a text field cannot use strokes: they need a
font. This turns the same drawings into one, so ordinary text (a text field
somebody is typing in, say) can be in the same hand as the written lines.

    python3 Tools/hand_font.py my-hand.json                 writes Hand.ttf next to it
    python3 Tools/hand_font.py my-hand.json -o App/Resources/Hand.ttf --family "My Hand"
    uv run Tools/hand_font.py my-hand.json                  the same, installing what it needs

Add the .ttf to the app target, list it under UIAppFonts in Info.plist, and
use it by the font name this prints: Font.custom("MyHand-Regular", size: 19).

Needs fonttools and shapely (pip install fonttools shapely).

What happens to a drawing:

  1. Each stroke is smoothed exactly as the pen smooths it (a curve through
     the midpoints of the finger's points).
  2. The curve is given the nib's thickness, with round ends. A font holds
     filled shapes, not lines, so this is the step that makes it a font.
  3. The strokes of one letter are merged into one shape and written as a
     glyph, sized so the font at size N has the same x-height as the pen at
     size N.

What the font does with them (these are OpenType features, the small
programs a font carries; iOS runs the first three without being asked):

  ccmp  an ellipsis becomes three full stops, as the pen writes it.
  liga  letters you drew joined ("th") replace the single letters.
  calt  the drawings of a letter take turns, so repeated letters do not look
        stamped. A font cannot roll dice; it walks a fixed cycle instead, and
        the same text always comes out the same, as it does from the pen.
  ss01  rare drawings (the "i" with a heart). Off unless the app asks: a
        font cannot use one "now and then", so they are opt-in. A second
        rare drawing of a letter is ss02, and so on.

The same borrowing as Hand.swift: a missing capital uses the small letter
(and the other way round), curly quotes and long dashes use the plain ones,
and accented letters use the letter without the accent.

What is lost: colour. A stroke drawn in red is in the font, in ink.
Characters that were never drawn are left out, and iOS fills them in from
the system font, so draw the whole list before using this for real text.

The same hand.json always gives the same bytes, so the file can be committed.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from shapely.geometry import LineString, Point
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
PEN_SOURCE = ROOT / "Sources" / "HandKit" / "Written.swift"
EDITOR_SOURCE = ROOT / "Sources" / "HandKit" / "HandEditor.swift"

UNITS_PER_EM = 1000
SCRIBBLE = "♡"
# The characters the my hand page asks for, if the Swift file cannot be read.
EDITOR_CHARACTERS = "abcdefghijklmnopqrstuvwxyz.,?'!-0123456789\":;()&/ABCDEFGHIJKLMNOPQRSTUVWXYZ"
# The pen's numbers, if the Swift file cannot be read. Sizes are in x-heights.
PEN_DEFAULTS = {
    "xHeightPerSize": 0.52,
    "nib": 0.13,
    "letterGap": 0.2,
    "wordGap": 0.62,
    "ascent": 1.95,
    "descent": 0.95,
}
# Characters that use another character's drawing, as Hand.plain does.
PLAIN = {
    "‘": "'", "’": "'",
    "“": '"', "”": '"',
    "–": "-", "—": "-",
}
# The drawings of a letter take turns over a cycle at least this long.
MIN_CYCLE = 3
MAX_CYCLE = 6
# The date written into the file: 1 January 2026, in seconds since 1904.
FIXED_DATE = 3850070400


def pen_numbers() -> dict[str, float]:
    """The pen's sizes, read from the Swift source so the two cannot drift apart."""
    numbers = dict(PEN_DEFAULTS)
    try:
        source = PEN_SOURCE.read_text()
    except OSError:
        return numbers
    for name in numbers:
        found = re.search(rf"static let {name}: CGFloat = ([0-9.]+)", source)
        if found:
            numbers[name] = float(found.group(1))
    return numbers


def editor_characters() -> str:
    """The list on the my hand page, read from the Swift source."""
    try:
        found = re.search(r'Array\("((?:[^"\\]|\\.)*)"\)\.map', EDITOR_SOURCE.read_text())
    except OSError:
        found = None
    return found.group(1).replace('\\"', '"') if found else EDITOR_CHARACTERS


def smooth(points: list[tuple[float, float]], steps: int = 8) -> list[tuple[float, float]]:
    """Written.smooth: a quadratic curve through the midpoints, with the points as the pull."""
    if len(points) < 3:
        return list(points)
    out = [points[0]]
    start = points[0]
    for i in range(1, len(points) - 1):
        control = points[i]
        end = ((points[i][0] + points[i + 1][0]) / 2, (points[i][1] + points[i + 1][1]) / 2)
        for step in range(1, steps + 1):
            t = step / steps
            a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t**2
            out.append((a * start[0] + b * control[0] + c * end[0], a * start[1] + b * control[1] + c * end[1]))
        start = end
    out.append(points[-1])
    return out


class Drawing:
    """One drawing from hand.json, as filled contours in font units."""

    def __init__(self, glyph: dict, pen: dict[str, float]):
        unit = pen["xHeightPerSize"] * UNITS_PER_EM
        radius = pen["nib"] * unit / 2
        # Half the gap between letters sits on each side of the ink.
        bearing = pen["letterGap"] * unit / 2
        self.rare = glyph.get("rare") is True
        self.advance = round((float(glyph.get("advance", 0)) + pen["letterGap"]) * unit)

        shapes = []
        for flat in glyph.get("strokes", []):
            # x0, y0, x1, y1, ... with y growing downwards; a font's y grows upwards.
            points = [(bearing + flat[i] * unit, -flat[i + 1] * unit) for i in range(0, len(flat) - 1, 2)]
            line = smooth(points)
            # Points that land on each other add nothing, and a line needs two that differ.
            line = [p for i, p in enumerate(line) if i == 0 or p != line[i - 1]]
            if not line:
                continue
            if len(line) == 1:
                shapes.append(Point(line[0]).buffer(radius, quad_segs=8))
            else:
                shapes.append(LineString(line).buffer(radius, quad_segs=8, cap_style="round", join_style="round"))

        self.contours: list[list[tuple[int, int]]] = []
        if not shapes:
            return
        merged = unary_union(shapes).simplify(0.6, preserve_topology=True)
        for polygon in getattr(merged, "geoms", [merged]):
            if polygon.is_empty:
                continue
            # TrueType fills what a clockwise contour encloses; a hole runs the other way.
            polygon = orient(polygon, sign=-1.0)
            for ring in [polygon.exterior, *polygon.interiors]:
                contour: list[tuple[int, int]] = []
                for x, y in list(ring.coords)[:-1]:
                    point = (round(x), round(y))
                    if not contour or contour[-1] != point:
                        contour.append(point)
                if len(contour) > 1 and contour[0] == contour[-1]:
                    contour.pop()
                if len(contour) >= 3:
                    self.contours.append(contour)

    def glyph(self):
        pen = TTGlyphPen(None)
        for contour in self.contours:
            pen.moveTo(contour[0])
            for point in contour[1:]:
                pen.lineTo(point)
            pen.closePath()
        return pen.glyph()


def name_of(key: str) -> str:
    """A glyph name for a key: uni0061 for "a", uni0074_uni0068 for "th"."""
    return "_".join(f"uni{ord(c):04X}" for c in key)


def build(hand: dict, pen: dict[str, float], family: str = "Hand"):
    """Returns the font and a few counts for the report."""
    unit = pen["xHeightPerSize"] * UNITS_PER_EM

    # The usual drawings and the rare ones, per key. A key with only rare
    # drawings writes with those, as the pen does.
    usual: dict[str, list[Drawing]] = {}
    rare: dict[str, list[Drawing]] = {}
    for key, glyphs in hand.get("glyphs", {}).items():
        # Named drawings (Hand.drawingPrefix) are pictures, not writing: a font has no use for them.
        if key.startswith("\ue000"):
            continue
        drawings = [d for d in (Drawing(g, pen) for g in glyphs) if d.contours]
        if not drawings:
            continue
        plain = [d for d in drawings if not d.rare]
        usual[key] = plain or drawings
        if plain:
            rare[key] = [d for d in drawings if d.rare]

    singles = sorted(k for k in usual if len(k) == 1)
    # A joined drawing is only usable where every letter in it can be typed.
    joined = sorted(k for k in usual if len(k) > 1 and all(c in usual for c in k))
    skipped = sorted(k for k in usual if len(k) > 1 and k not in joined)

    # Every glyph has one form per step of the cycle, so the step can be
    # carried from one glyph to the next. Form k shows drawing k mod n.
    most = max((len(usual[k]) for k in singles + joined), default=1)
    cycle = max(MIN_CYCLE, min(MAX_CYCLE, most))

    order = [".notdef"]
    glyf = {".notdef": TTGlyphPen(None).glyph()}
    metrics = {".notdef": (round(unit), 0)}
    forms: list[list[str]] = [[] for _ in range(cycle)]

    def add(name: str, drawing: Drawing | None, advance: int):
        order.append(name)
        glyf[name] = drawing.glyph() if drawing else TTGlyphPen(None).glyph()
        left = min((x for contour in drawing.contours for x, _ in contour), default=0) if drawing else 0
        metrics[name] = (advance, left)

    def add_forms(base: str, drawings: list[Drawing] | None, advance: int = 0):
        for step in range(cycle):
            name = base if step == 0 else f"{base}.{step}"
            drawing = drawings[step % len(drawings)] if drawings else None
            add(name, drawing, drawing.advance if drawing else advance)
            forms[step].append(name)

    # The gap between words, less the half gaps the letters either side already carry.
    add_forms("space", None, round((pen["wordGap"] - pen["letterGap"]) * unit))
    for key in singles + joined:
        add_forms(name_of(key), usual[key])

    rare_sets: list[list[tuple[str, str]]] = []
    for key in singles + joined:
        for index, drawing in enumerate(rare.get(key, [])):
            name = f"{name_of(key)}.rare{index + 1}"
            add(name, drawing, drawing.advance)
            while len(rare_sets) <= index:
                rare_sets.append([])
            rare_sets[index].append((name_of(key), name))
    rare_sets = rare_sets[:20]

    # Which character shows which glyph.
    cmap: dict[int, str] = {0x20: "space", 0xA0: "space"}
    for key in singles:
        cmap[ord(key)] = name_of(key)
    for key in singles:
        for other in (key.lower(), key.upper()):
            if len(other) == 1:
                cmap.setdefault(ord(other), name_of(key))
    for fancy, plain in PLAIN.items():
        if ord(plain) in cmap:
            cmap.setdefault(ord(fancy), cmap[ord(plain)])
    # Accented letters, through Latin Extended-A, write as the letter alone.
    for code in range(0xC0, 0x180):
        base = "".join(c for c in unicodedata.normalize("NFD", chr(code)) if not unicodedata.combining(c))
        if len(base) == 1 and base != chr(code) and ord(base) in cmap:
            cmap.setdefault(code, cmap[ord(base)])

    features: list[str] = ["languagesystem DFLT dflt;", "languagesystem latn dflt;"]
    if ord(".") in cmap:
        add("ellipsis", None, 0)
        cmap[0x2026] = "ellipsis"
        stop = cmap[ord(".")]
        features.append(f"feature ccmp {{ sub ellipsis by {stop} {stop} {stop}; }} ccmp;")
    if joined:
        rules = " ".join(f"sub {' '.join(cmap[ord(c)] for c in key)} by {name_of(key)};" for key in joined)
        features.append(f"feature liga {{ {rules} }} liga;")
    for index, pairs in enumerate(rare_sets):
        rules = " ".join(f"sub {plain} by {fancy};" for plain, fancy in pairs)
        features.append(f"feature ss{index + 1:02d} {{ {rules} }} ss{index + 1:02d};")

    # The cycle. A glyph after one at step k becomes step k + 1; after the last
    # step it stays at step 0. Where the last step and step 0 show the same
    # drawing, a doubled letter would get it twice, so that case goes first
    # and moves on to step 1.
    rules = []
    for key in singles + joined:
        count = len(usual[key])
        if count > 1 and (cycle - 1) % count == 0:
            base = name_of(key)
            rules.append(f"sub {base}.{cycle - 1} {base}' by {base}.1;")
    for step in range(1, cycle):
        rules.append(f"sub @form{step - 1} @form0' by @form{step};")
    classes = " ".join(f"@form{step} = [{' '.join(names)}];" for step, names in enumerate(forms))
    features.append(f"{classes} feature calt {{ {' '.join(rules)} }} calt;")

    ascent = round(pen["ascent"] * unit)
    descent = round(pen["descent"] * unit)
    style = "Regular"
    postscript = family.replace(" ", "") + "-" + style

    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap(cmap)
    builder.setupGlyf(glyf)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=ascent, descent=-descent, lineGap=0)
    builder.setupNameTable({"familyName": family, "styleName": style, "psName": postscript, "fullName": f"{family} {style}"})
    builder.setupOS2(
        version=4,
        sTypoAscender=ascent, sTypoDescender=-descent, sTypoLineGap=0,
        usWinAscent=ascent, usWinDescent=descent,
        sxHeight=round(unit), sCapHeight=round(unit * 1.8),
        fsSelection=0x40 | 0x80,  # regular, and use the typo metrics above
        achVendID="YRPN",
    )
    builder.setupPost()
    addOpenTypeFeaturesFromString(builder.font, "\n".join(features))
    # No dates, so the same hand always gives the same file.
    builder.updateHead(created=FIXED_DATE, modified=FIXED_DATE)
    builder.font.recalcTimestamp = False

    report = {
        "drawn": singles,
        "joined": joined,
        "skipped": skipped,
        "drawings": sum(len(usual[k]) for k in singles + joined),
        "rare": sum(len(pairs) for pairs in rare_sets),
        "cycle": cycle,
        "postscript": postscript,
    }
    return builder.font, report


def main() -> int:
    parser = argparse.ArgumentParser(description="Turn hand.json into a TrueType font.")
    parser.add_argument("hand", type=Path, help="the hand file: hand.json, as sent from the drawing page")
    parser.add_argument("-o", "--output", type=Path, default=None, help="where to write the font (default: Hand.ttf next to the hand file)")
    parser.add_argument("--family", default="Hand", help="the font's family name")
    arguments = parser.parse_args()
    if arguments.output is None:
        arguments.output = arguments.hand.with_name("Hand.ttf")

    try:
        hand = json.loads(arguments.hand.read_text())
    except OSError:
        print(f"No hand at {arguments.hand}.", file=sys.stderr)
        print('Draw the letters on the drawing page (HandEditor), tap "send my hand as a file", and pass that file here.', file=sys.stderr)
        return 1
    except json.JSONDecodeError as error:
        print(f"{arguments.hand} is not a hand: {error}", file=sys.stderr)
        return 1
    if not isinstance(hand, dict) or not isinstance(hand.get("glyphs"), dict):
        print(f"{arguments.hand} is not a hand: it has no glyphs.", file=sys.stderr)
        return 1

    font, report = build(hand, pen_numbers(), arguments.family)
    if not report["drawn"]:
        print("Nothing has been drawn yet, so there is no font to make.", file=sys.stderr)
        return 1
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    font.save(arguments.output)

    print(f"{arguments.output}  ({arguments.output.stat().st_size // 1024 or 1} KB)")
    print(f"  font name     {report['postscript']}")
    print(f"  characters    {len(report['drawn'])} drawn, {report['drawings']} drawings, taking turns over {report['cycle']}")
    if report["joined"]:
        print(f"  joined        {' '.join(report['joined'])}")
    if report["rare"]:
        print(f"  rare          {report['rare']} (ss01 and up, off unless asked for)")
    if report["skipped"]:
        print(f"  left out      {' '.join(report['skipped'])}: joined letters need each single letter drawn too")
    # A capital borrows the small letter, so only a letter missing in both cases is missing.
    drawn = {c for key in report["drawn"] for c in (key, key.lower(), key.upper())}
    missing = [c for c in editor_characters() if c not in drawn]
    if missing:
        print(f"  not drawn     {' '.join(missing)}")
        print("                iOS shows these in the system font. Draw them before using this for real text.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
