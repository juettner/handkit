#!/usr/bin/env python3
"""
hand_subset.py: a small hand that can write one line and nothing else.

For shipping a line of handwriting inside an app without shipping the whole
hand: the Handkit app's welcome page writes "your handwriting, kept" with
App/HandkitApp/welcome.json if that file is there.

    python3 Tools/hand_subset.py my-hand.json "your handwriting, kept" -o App/HandkitApp/welcome.json

It keeps the drawings of the characters in the text (a capital's small letter
too, since the pen borrows it), and the joined letters the text contains
("th"). Scribbles, pictures, the signature and every other letter are left
out. Needs nothing but Python.
"""

import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Cut a hand down to the letters of one line.")
    parser.add_argument("hand", help="the whole hand: a hand.json")
    parser.add_argument("text", help="the line the small hand must be able to write")
    parser.add_argument("-o", "--out", required=True, help="where to write the small hand")
    parser.add_argument("--most", type=int, default=3, help="the most drawings kept of each character (default 3)")
    args = parser.parse_args()

    with open(args.hand, encoding="utf-8") as file:
        glyphs = json.load(file).get("glyphs", {})

    text = "".join(args.text.split())
    wanted = set(text) | set(text.lower())
    # Named pictures are kept under a key that starts with a private-use
    # character (Hand.drawingPrefix), so "longer than one" alone is not enough.
    joined = {key for key in glyphs if len(key) > 1 and key[0] != "" and key in args.text.lower()}

    kept = {key: glyphs[key][: args.most] for key in sorted(wanted | joined) if glyphs.get(key)}
    missing = sorted(c for c in set(text) if c not in kept and c.lower() not in kept)
    if missing:
        sys.exit(f"hand_subset: the hand has no drawing of: {' '.join(missing)}")

    with open(args.out, "w", encoding="utf-8") as file:
        json.dump({"glyphs": kept}, file, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {args.out}: {len(kept)} characters, {sum(len(v) for v in kept.values())} drawings")


if __name__ == "__main__":
    main()
