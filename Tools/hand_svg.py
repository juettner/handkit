#!/usr/bin/env python3
"""
hand_svg.py: a line written by the pen, as a picture a web page can show.

The pen (Sources/HandKit/Handwriting.swift) writes a line on an iPhone,
stroke by stroke. A web page has no pen. This does the pen's arithmetic here,
once, for one text, and writes the result down as an SVG file: every stroke
in its place, with a small stylesheet inside the file that draws them one
after another, at the pen's pace. The browser only plays it back, so the page
needs no script, and the hand file itself never leaves your machine: the
picture holds the strokes of this one line and nothing else.

    python3 Tools/hand_svg.py my-hand.json "good morning, love"            writes written.svg
    python3 Tools/hand_svg.py my-hand.json "one line\\nand another" -o note.svg --center
    python3 Tools/hand_svg.py my-hand.json "P.S." -o name.svg --size 48 --plain
    python3 Tools/hand_svg.py my-hand.json "good morning" --speed 0        already written, nothing moves

Then, in the page (the width and height are printed when the file is made):

    <img src="note.svg" width="412" height="96" alt="one line and another">

Needs nothing but Python.

Reduce Motion. Somebody who has asked their device for less motion should be
shown the line already written. The picture does that by itself when it is
opened directly, but a browser does not always pass the setting on to a
picture shown with <img> (Chrome, tested, does not). So make a second file
with --speed 0 and let the page choose, which always works:

    <picture>
      <source srcset="note-still.svg" media="(prefers-reduced-motion: reduce)">
      <img src="note.svg" width="412" height="96" alt="one line and another">
    </picture>

What is kept from the pen (Written.swift, followed line for line):

  - which drawing of a letter is used, the rare ones and the scribble
    included (--plain turns those off, --seed picks differently);
  - the small differences in how each letter is put down, and each letter's
    own shade and thickness of ink;
  - a stroke's own colour and its own line, if it was drawn with one;
  - crossing out: "you looked ~~nice~~ incredible";
  - the rhythm: longer strokes take longer, the pen lifts between strokes
    and words and rests after a full stop; and the ink drying behind the nib.

What is not:

  - the line breaks where this says (--width, or a "\\n" in the text), not
    where the reader's screen is narrow. The picture shrinks to fit instead.
  - it is the same every time it is shown. The app can write a text a
    different way tomorrow; a file cannot. Make a few and take turns if that
    matters.
  - wet ink is darker but not wider (on a web page that is a quarter of a
    pixel), and there is no signature.

The pen's numbers are read out of Written.swift, as hand_font.py does, so
the app and the picture agree.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PEN_SOURCE = ROOT / "Sources" / "HandKit" / "Written.swift"

SCRIBBLE = "♡"
# Named drawings (an envelope, the app's icon) are kept under keys that start
# with this character (Hand.drawingPrefix). They are not writing.
DRAWING_PREFIX = ""
STRIKE = "~~"
# The pen's numbers, if the Swift file cannot be read. Sizes are in x-heights.
PEN_DEFAULTS = {
    "lettersPerSecond": 15.0,
    "xHeightPerSize": 0.52,
    "nib": 0.13,
    "letterGap": 0.2,
    "wordGap": 0.62,
    "lineHeight": 2.9,
    "ascent": 1.95,
    "descent": 0.95,
    "rareChance": 0.035,
    "occasionalChance": 0.2,
    "scribbleChance": 0.2,
    "dryTime": 0.7,
    "strikeHeight": 0.48,
}
# Characters that use another character's drawing, as Hand.plain does.
PLAIN = {
    "‘": "'", "’": "'",
    "“": '"', "”": '"',
    "–": "-", "—": "-",
}
# HandStyle.journal's ink.
INK = "1E1A17"
# How far the lines of the picture may stray from the pen's curve, in
# x-heights. A curve is written to the file as many short straight lines;
# this is about a tenth of a pixel at reading size, which nobody can see, and
# it keeps the file a quarter of the size.
FLATNESS = 0.006


def pen_numbers() -> dict[str, float]:
    """The pen's numbers, read from the Swift source so the two cannot drift apart."""
    numbers = dict(PEN_DEFAULTS)
    try:
        source = PEN_SOURCE.read_text()
    except OSError:
        return numbers
    for name in numbers:
        found = re.search(rf"static let {name}: \w+ = ([0-9.]+)", source)
        if found:
            numbers[name] = float(found.group(1))
    return numbers


# --- The hand (Hand.swift) ---------------------------------------------------


def plain(character: str) -> str:
    """Hand.plain: the key a character is looked up under."""
    if character in PLAIN:
        return PLAIN[character]
    # Accents are dropped: split the letter from its accent, keep the letter.
    return "".join(c for c in unicodedata.normalize("NFD", character) if not unicodedata.combining(c))


def drawings_for(glyphs: dict, character: str) -> list | None:
    """Hand.drawings(for:): a missing capital borrows the small letter, and the other way round."""
    for key in (character, character.lower(), character.upper()):
        if glyphs.get(key):
            return glyphs[key]
    return None


def pieces(glyphs: dict, word: str) -> tuple[list[tuple[list, int]], list[str]]:
    """Hand.pieces(of:skippingUnknown: true): the word as the drawings the pen
    will use, letters drawn joined ("th") first. Also the characters left out."""
    letters = [c for character in word for c in plain(character)]
    longest = max((len(key) for key in glyphs if not key.startswith(DRAWING_PREFIX)), default=1)
    out: list[tuple[list, int]] = []
    missing: list[str] = []
    at = 0
    while at < len(letters):
        taken = False
        if longest > 1 and len(letters) - at > 1:
            for length in range(min(longest, len(letters) - at), 1, -1):
                joined = glyphs.get("".join(letters[at:at + length]))
                if joined:
                    out.append((joined, length))
                    at += length
                    taken = True
                    break
        if taken:
            continue
        single = drawings_for(glyphs, letters[at])
        if single:
            out.append((single, 1))
        else:
            missing.append(letters[at])
        at += 1
    return out, missing


def struck(text: str) -> list[tuple[str, bool]]:
    """Hand.struck: the text cut at its crossing-out marks."""
    parts = text.split(STRIKE)
    # An even number of parts means the last mark never closed: put it back.
    if len(parts) % 2 == 0:
        tail = parts.pop()
        parts[-1] += STRIKE + tail
    return [(part, index % 2 == 1) for index, part in enumerate(parts) if part]


def words_of(text: str) -> tuple[list[str], set[int], set[int]]:
    """Written.words(of:): the words, which are crossed out, and which follow a line break."""
    words: list[str] = []
    crossed: set[int] = set()
    breaks: set[int] = set()
    word = ""
    word_struck = False
    line_broke = False
    for part, part_struck in struck(text.replace("…", "...")) + [(" ", False)]:
        for character in part:
            if not character.isspace():
                word += character
                if part_struck:
                    word_struck = True
                continue
            if word:
                if line_broke and words:
                    breaks.add(len(words))
                if word_struck:
                    crossed.add(len(words))
                words.append(word)
                word = ""
                word_struck = False
                line_broke = False
            if character in "\n\r\x0b\x0c\x85  ":
                line_broke = True
    return words, crossed, breaks


# --- The dice (Seeded, in Written.swift) -------------------------------------

MASK = (1 << 64) - 1


class Seeded:
    """The same numbers for the same text, every time. Swift's integers wrap
    round at 64 bits; Python's grow, so each step is cut back to 64 (& MASK)."""

    def __init__(self, seed: str) -> None:
        state = 14695981039346656037
        for byte in seed.encode("utf-8"):
            state ^= byte
            state = (state * 1099511628211) & MASK
        self.state = state

    def unit(self) -> float:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        z ^= z >> 31
        return (z >> 11) / 9007199254740992

    def between(self, low: float, high: float) -> float:
        return low + (high - low) * self.unit()


# --- The writing (Written.init) ----------------------------------------------


class Mark:
    """One pen stroke, placed on the page and on the clock."""

    def __init__(self, points, start, beats, ink, width, color, row, letter):
        self.points = points
        self.start = start
        self.duration = beats
        self.ink = ink
        self.width = width
        self.color = color      # 0xRRGGBB, or None for ordinary ink
        self.row = row          # which line of the page it is on
        self.letter = letter    # strokes of one letter share a number


def glyph_width(glyph: dict, stroke: int) -> float:
    widths = glyph.get("widths") or []
    return widths[stroke] if stroke < len(widths) and widths[stroke] > 0 else 1.0


def glyph_color(glyph: dict, stroke: int) -> int | None:
    colors = glyph.get("colors") or []
    return colors[stroke] if stroke < len(colors) and colors[stroke] >= 0 else None


def frequency(glyph: dict) -> str:
    return "rare" if glyph.get("rare") else "occasional" if glyph.get("occasional") else "usual"


def write(text, glyphs, pen, x_height, width, letters_per_second, playful, seed, looseness, slant):
    """Written.init, without the signature. The names and the order are the
    Swift's: the dice must be thrown in the same order to land the same way."""
    random = Seeded(text if seed == 0 else f"{text}#{seed}")
    words, crossed, breaks = words_of(text)
    scribbles = random.unit() < pen["scribbleChance"]
    if playful and scribbles and words and glyphs.get(SCRIBBLE):
        words.append(SCRIBBLE)

    x = 0.0
    baseline = pen["ascent"] * x_height
    row = 0
    widest = 0.0
    clock = 0.0
    letter_count = 0
    letter_number = 0
    previous = None
    broken = False
    marks: list[Mark] = []
    missing: list[str] = []
    # How far the ink runs on each row, for centring.
    row_widths: dict[int, float] = {}
    # The words crossed out and not yet struck through: [from, to, baseline, row].
    to_strike: list[list] = []

    def strike_through():
        nonlocal clock, letter_number
        for number, (start, end, base, on_row) in enumerate(to_strike):
            clock += 3 if number == 0 else 0.6
            start -= 0.12 * x_height
            end += 0.12 * x_height
            length = (end - start) / x_height
            height = base - (pen["strikeHeight"] + random.between(-0.06, 0.06)) * x_height
            rise = random.between(-0.09, 0.09) * x_height
            steps = max(2, int(length / 0.7))
            points = []
            for step in range(steps + 1):
                along = step / steps
                wobble = random.between(-0.035, 0.035) * x_height
                points.append((start + (end - start) * along, height + rise * (along - 0.5) + wobble))
            beats = 0.25 + 0.3 * max(0.0, length) ** 0.75
            letter_number += 1
            marks.append(Mark(points, clock, beats, 0.95, pen["nib"] * x_height, None, on_row, letter_number))
            clock += beats
        to_strike.clear()

    for number, word in enumerate(words):
        word_pieces, left_out = pieces(glyphs, word)
        missing += left_out
        if number in breaks:
            broken = True
        if not word_pieces:
            continue
        crossed_out = number in crossed
        if not crossed_out and to_strike:
            strike_through()
        rare_used = False
        letters = []
        for drawings, _ in word_pieces:
            roll = random.unit()
            pick = random.unit()
            usual = [g for g in drawings if frequency(g) == "usual"]
            occasional = [g for g in drawings if frequency(g) == "occasional"]
            rare = [g for g in drawings if frequency(g) == "rare"]
            pool = usual or occasional or rare
            if playful and usual:
                if rare and not rare_used and roll < pen["rareChance"]:
                    pool = rare
                    rare_used = True
                elif occasional and roll < pen["rareChance"] + pen["occasionalChance"]:
                    pool = occasional
            letters.append(pool[int(pick * len(pool)) % len(pool)])
        word_width = sum(g["advance"] * x_height for g in letters) + max(0, len(letters) - 1) * pen["letterGap"] * x_height

        if x > 0:
            x += pen["wordGap"] * x_height
            if broken or x + word_width > width:
                x = 0.0
                baseline += pen["lineHeight"] * x_height
                row += 1
        broken = False

        if previous is not None:
            clock += 1.6
            if previous in ",;:":
                clock += 3
            if previous in ".?!":
                clock += 6
        lean = random.between(-0.1, 0.02)

        for index, glyph in enumerate(letters):
            advance = glyph["advance"] * x_height
            if x > 0 and x + advance > width:
                x = 0.0
                baseline += pen["lineHeight"] * x_height
                row += 1
            if index > 0:
                clock += 0.45

            lift = random.between(-0.05, 0.05) * looseness * x_height
            scale = 1 + random.between(-0.04, 0.04) * looseness
            tilt = random.between(-0.035, 0.035) * looseness
            ink = min(1.0, max(0.72, 0.93 + lean + random.between(-0.07, 0.07)))
            nib = pen["nib"] * x_height * random.between(0.92, 1.08)
            origin = (x, baseline + lift)
            pivot = (glyph["advance"] / 2, -0.5)
            letter_number += 1

            stroke_index = -1
            for flat in glyph["strokes"]:
                stroke_index += 1
                stroke = [(flat[i], flat[i + 1]) for i in range(0, len(flat) - 1, 2)]
                if not stroke:
                    continue
                if stroke_index > 0:
                    clock += 0.3
                length = sum(math.dist(stroke[i], stroke[i - 1]) for i in range(1, len(stroke)))
                beats = 0.25 + 0.5 * length ** 0.75
                placed = []
                for px, py in stroke:
                    dx = (px - pivot[0]) * scale
                    dy = (py - pivot[1]) * scale
                    ry = dx * math.sin(tilt) + dy * math.cos(tilt) + pivot[1]
                    rx = dx * math.cos(tilt) - dy * math.sin(tilt) + pivot[0] - ry * slant
                    placed.append((origin[0] + rx * x_height, origin[1] + ry * x_height))
                marks.append(Mark(placed, clock, beats, ink, nib * glyph_width(glyph, stroke_index), glyph_color(glyph, stroke_index), row, letter_number))
                clock += beats

            if crossed_out:
                if to_strike and to_strike[-1][2] == baseline:
                    to_strike[-1][1] = x + advance
                else:
                    to_strike.append([x, x + advance, baseline, row])
            x += advance
            widest = max(widest, x)
            row_widths[row] = x
            if index < len(letters) - 1:
                x += pen["letterGap"] * x_height
            letter_count += word_pieces[index][1]
        previous = word[-1]
    if to_strike:
        strike_through()

    seconds = max(0.4, letter_count / letters_per_second) / clock if clock > 0 and letters_per_second > 0 else 0.0
    for mark in marks:
        mark.start *= seconds
        mark.duration *= seconds
    size = (widest, baseline + pen["descent"] * x_height)
    return marks, size, clock * seconds, row_widths, missing


# --- The picture -------------------------------------------------------------


def smooth(points: list[tuple[float, float]], steps: int = 8) -> list[tuple[float, float]]:
    """Written.smooth: a quadratic curve through the midpoints, with the points
    as the pull. Returned as many short straight lines."""
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


def thin(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    """Drops the points a straight line can stand in for (Ramer-Douglas-Peucker):
    keep the two ends, find the point furthest from the line between them, and
    if it is further than the tolerance keep it too and do the same either side."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    spans = [(0, len(points) - 1)]
    while spans:
        first, last = spans.pop()
        (ax, ay), (bx, by) = points[first], points[last]
        length = math.hypot(bx - ax, by - ay)
        furthest, at = 0.0, None
        for i in range(first + 1, last):
            px, py = points[i]
            if length == 0:
                distance = math.hypot(px - ax, py - ay)
            else:
                # How far along the line the point is, kept between its two ends.
                along = max(0.0, min(1.0, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / length**2))
                distance = math.hypot(px - (ax + along * (bx - ax)), py - (ay + along * (by - ay)))
            if distance > furthest:
                furthest, at = distance, i
        if at is not None and furthest > tolerance:
            keep[at] = True
            spans += [(first, at), (at, last)]
    return [point for point, kept in zip(points, keep) if kept]


def number(value: float) -> str:
    """A number as short as SVG allows: two decimals, no "0" before the point, no trailing zeros."""
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    if text in ("", "-0"):
        return "0"
    return text.replace("0.", ".", 1) if text.startswith(("0.", "-0.")) else text


def path_data(points: list[tuple[float, float]]) -> str:
    """The stroke as SVG path commands: M (move to) the start, then l (line
    by) for each step. Steps are measured between rounded positions, so the
    rounding never adds up along the stroke."""
    rounded = [(round(x, 2), round(y, 2)) for x, y in points]
    out = f"M{number(rounded[0][0])} {number(rounded[0][1])}"
    if len(rounded) == 1 or all(point == rounded[0] for point in rounded):
        # A dot. A line of no length is not drawn by every browser; a very short one is.
        return out + "l.01 0"
    out += "l"
    here = rounded[0]
    steps = []
    for point in rounded[1:]:
        steps.append(f"{number(point[0] - here[0])} {number(point[1] - here[1])}")
        here = point
    # A minus sign separates two numbers as well as a space does, and is already there.
    return out + " ".join(steps).replace(" -", "-")


def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def seconds(value: float) -> str:
    return number(value) + "s"


# The stylesheet inside the picture. It is the whole of the animation.
#
#   pathLength="1" on every stroke tells the browser to measure that stroke
#   as if it were 1 long, whatever its real length. A dashed line with a dash
#   of 1 is then exactly the whole stroke, and stroke-dashoffset slides the
#   dash along: at 1 none of it is on the stroke, at 0 all of it is. Sliding
#   it from 1 to 0 is the pen moving.
#
#   Each stroke carries its own start (--s) and how long it takes (--d), and
#   each letter its shade once dry (--i). "write" runs from --s for --d;
#   "dry" starts where it ends and takes the ink from full strength to --i.
#
#   Before its turn a stroke is hidden (the "from" of write, held because of
#   "both"), and afterwards it stays as "to" left it.
STYLE = """<style>
path{opacity:var(--i)}
@media (prefers-reduced-motion:no-preference){
path{stroke-dasharray:1 2;animation:write var(--d) cubic-bezier(.25,.4,.6,1) var(--s) both,dry DRY linear calc(var(--s) + var(--d)) forwards}
@keyframes write{from{stroke-dashoffset:1;opacity:1;visibility:hidden}to{stroke-dashoffset:0;opacity:1;visibility:visible}}
@keyframes dry{from{opacity:1}to{opacity:var(--i)}}
}
</style>"""


def picture(marks, size, row_widths, x_height, ink, label, delay, dry_time, center, moving) -> tuple[str, int, int]:
    """The SVG file, and its width and height."""
    # Each row slid to the middle, if asked.
    shift = {row: (size[0] - width) / 2 if center else 0.0 for row, width in row_widths.items()}
    lines = []
    left, right, top, bottom = 0.0, size[0], 0.0, size[1]
    for mark in marks:
        dx = shift.get(mark.row, 0.0)
        points = thin(smooth([(x + dx, y) for x, y in mark.points]), FLATNESS * x_height)
        half = mark.width / 2
        left = min(left, min(x for x, _ in points) - half)
        right = max(right, max(x for x, _ in points) + half)
        top = min(top, min(y for _, y in points) - half)
        bottom = max(bottom, max(y for _, y in points) + half)
        lines.append((mark, path_data(points)))

    # A little room all round, so no round end of a stroke is cut off.
    edge = 0.06 * x_height
    left, top = math.floor(left - edge), math.floor(top - edge)
    width, height = math.ceil(right + edge) - left, math.ceil(bottom + edge) - top

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{left} {top} {width} {height}" width="{width}" height="{height}" '
        f'role="img" aria-label="{escape(label)}" fill="none" stroke="#{ink}" stroke-linecap="round" stroke-linejoin="round">',
        f"<title>{escape(label)}</title>",
    ]
    if moving:
        out.append(STYLE.replace("DRY", seconds(dry_time)))
    # The strokes of one letter go in one group (<g>): they share a shade and, mostly, a thickness.
    letter = None
    for mark, data in lines:
        if mark.letter != letter:
            if letter is not None:
                out.append("</g>")
            letter = mark.letter
            group_width = mark.width
            shade = f' style="--i:{number(mark.ink)}"' if moving else f' opacity="{number(mark.ink)}"'
            out.append(f'<g stroke-width="{number(group_width)}"{shade}>')
        attributes = ""
        if mark.color is not None:
            attributes += f' stroke="#{mark.color:06X}"'
        if abs(mark.width - group_width) > 0.005:
            attributes += f' stroke-width="{number(mark.width)}"'
        if moving:
            attributes += f' pathLength="1" style="--s:{seconds(mark.start + delay)};--d:{seconds(max(mark.duration, 0.01))}"'
        out.append(f'<path{attributes} d="{data}"/>')
    if letter is not None:
        out.append("</g>")
    out.append("</svg>")
    return "\n".join(out) + "\n", width, height


def main() -> int:
    pen = pen_numbers()
    parser = argparse.ArgumentParser(description="A line written by the pen, as an SVG a web page can show.")
    parser.add_argument("hand", type=Path, help="the hand.json")
    parser.add_argument("text", help='what to write. "\\n" starts a new line; ~~two tildes~~ cross out.')
    parser.add_argument("-o", "--output", type=Path, default=Path("written.svg"), help="where to write the picture (default: written.svg)")
    parser.add_argument("--size", type=float, default=30, help="the type size a typed line of the same height would have (default: 30)")
    parser.add_argument("--width", type=float, default=math.inf, help="break lines at this width, in the same units as --size (default: only at \\n)")
    parser.add_argument("--center", action="store_true", help="put each line in the middle, not at the left")
    parser.add_argument("--ink", default=INK, help=f"the colour of ordinary ink, as RRGGBB (default: {INK})")
    parser.add_argument("--speed", type=float, default=pen["lettersPerSecond"], help="letters per second; 0 for a line already written (default: %(default)s)")
    parser.add_argument("--delay", type=float, default=0.3, help="seconds before the pen starts (default: %(default)s)")
    parser.add_argument("--dry", type=float, default=pen["dryTime"], help="seconds the ink stays wet (default: %(default)s)")
    parser.add_argument("--seed", type=int, default=0, help="write the same text a different way")
    parser.add_argument("--plain", action="store_true", help="no rare drawings and no scribble")
    parser.add_argument("--looseness", type=float, default=1, help="how unevenly the letters are put down (default: 1)")
    parser.add_argument("--slant", type=float, default=0, help="how far the letters lean forward; 0.15 is a hurry (default: 0)")
    arguments = parser.parse_args()

    try:
        glyphs = json.loads(arguments.hand.read_text())["glyphs"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"{arguments.hand} is not a hand file: {error}", file=sys.stderr)
        return 1
    ink = arguments.ink.lstrip("#").upper()
    if not re.fullmatch(r"[0-9A-F]{6}", ink):
        print(f"--ink wants six hex digits, such as {INK}", file=sys.stderr)
        return 1

    # Typed in a shell, a new line is easiest written as the two characters \n.
    text = arguments.text.replace("\\n", "\n")
    x_height = arguments.size * pen["xHeightPerSize"]
    marks, size, duration, row_widths, missing = write(
        text, glyphs, pen, x_height, arguments.width, arguments.speed,
        not arguments.plain, arguments.seed, arguments.looseness, arguments.slant,
    )
    if not marks:
        print("Nothing to write: the hand has no drawing for any character of that text.", file=sys.stderr)
        return 1

    # What a screen reader says, and what shows if the picture does not: the words, without the crossing-out marks.
    label = " ".join("".join(part for part, _ in struck(text)).split())
    moving = arguments.speed > 0
    svg, width, height = picture(
        marks, size, row_widths, x_height, ink, label,
        arguments.delay, arguments.dry, arguments.center, moving,
    )
    arguments.output.write_text(svg)

    print(f"{arguments.output}: {width} x {height}, {len(marks)} strokes, {len(svg.encode()) / 1024:.1f} KB")
    if moving:
        print(f"The pen starts after {arguments.delay:g}s and is done at {arguments.delay + duration:.1f}s.")
    if missing:
        print("Left out (never drawn): " + " ".join(dict.fromkeys(missing)))
    print(f'<img src="{arguments.output.name}" width="{width}" height="{height}" alt="{escape(label)}">')
    return 0


if __name__ == "__main__":
    sys.exit(main())
