# HandKit

Handwriting as data, and a pen that writes it.

A handwriting font looks too clean: every "e" is the same "e". HandKit keeps
the pen strokes you actually drew, letter by letter, and writes a line with
them stroke by stroke, in the order and direction you made them. Each letter
is nudged a little differently, repeated letters take turns between your
drawings of them, a rare drawing (an "i" dotted with a heart) turns up now
and then, and sometimes a scribble follows the line.

Pulled out of [your-person](https://github.com/juettner/your-person) so other
apps can use it. No dependencies. iOS 17+ (the pen also builds for macOS 14+).

## What is in it

| | |
| --- | --- |
| `Hand`, `Glyph` | The data. Plain `Codable` JSON: ship it in the app, save it, or send it over a network. |
| `Handwriting` | The view. `Handwriting(text:hand:)` writes a line with the pen. |
| `Written` | The arithmetic behind the view: where each stroke goes and when. No views; testable. |
| `Sketch` | The same drawing, made by the pen while you watch. |
| `GlyphView` | Shows one drawing as a picture, fitted to its frame. For drawings kept under a name (`hand.drawings(named: "envelope")`): pass their names to `HandEditor(drawings:)` and they get a row of their own on the drawing page. |
| `HandStore` | Loads `hand.json` (drawn on this phone if there is one, otherwise the one shipped in the app) and saves what the editor draws. |
| `HandEditor` | The drawing page: draw each character on a ruled square, try a sentence, send the hand as a file. It also asks for the app's icon (the "app icon" entry in the row of pictures): there the square is the icon, and "send the icon" hands over the 1024 x 1024 `icon.png`. `HandEditor(icon: false)` leaves that out. iOS only. |
| `SignaturePad` | The signing page: sign on a line, keep a few. Each is a `Glyph`, and `Handwriting(signatures:)` signs under a line with one of them. iOS only. |
| `Tools/hand_font.py` | Turns a `hand.json` into a real `.ttf`, for text that cannot be drawn stroke by stroke (a text field being typed in). |

## Try it

```bash
open Demo/HandKitDemo.xcodeproj
```

Pick an iPhone simulator and Run. The demo is one page that writes whatever
you type in your handwriting, and a word that opens the drawing page. All of
it is in `Demo/HandKitDemo/DemoApp.swift`, about a hundred lines.

## Adding it to an app

In Xcode: **File > Add Package Dependencies...**, then either paste this
repository's URL, or choose **Add Local...** and pick this folder if it sits
next to your app on disk (handy while both are changing). Tick the `HandKit`
library for your app target.

## Using it

```swift
import HandKit
import SwiftUI

struct Note: View {
    @ObservedObject private var hands = HandStore.shared

    var body: some View {
        if let hand = hands.active, hand.covers("good morning, love") {
            Handwriting(text: "good morning, love", hand: hand, size: 30)
        } else {
            Text("good morning, love")   // no hand shipped yet, or a letter is missing
        }
    }
}
```

`Handwriting` takes the hand as a value, so it does not care where the hand
came from. One fetched from a server works the same way:

```swift
let hand = Hand(data: bytesFromTheServer)
```

Options on `Handwriting`: `size` (the point size a typed line of the same
height would have), `ink` (colour), `speed` (letters per second; 0 shows the
line already written), `haptics`, `playful` (the rare drawings and scribbles),
`seed` (write the same text a different way), `looseness` (how unevenly the
letters are put down; 1 is the usual hand), `slant` (how far they lean
forward; 0.15 is a hurry), `dryTime` (how long the ink stays wet and dark
behind the nib) and `onDone`.

**Crossing out.** Put two tildes on each side of a word, as in
`"you looked ~~nice~~ incredible"`, and the pen writes it, stops for a
moment, and draws a line through it before going on. The tildes are never
written. `Hand.unstruck(text)` gives the words without the marks (for
reading aloud, or for showing where nothing can be struck through), and
`Hand.struck(text)` the pieces and which of them are crossed out.

**A drawing, drawn.** `GlyphView` shows a named drawing as a picture;
`Sketch` has the pen make it while you watch, stroke by stroke:

```swift
if let doodle = hand.drawings(named: "doodle").first {
    Sketch(doodle, duration: 1.4).frame(width: 60, height: 60)
}
```

A character the hand has no drawing for is left out. `hand.covers(text)` says
whether a text can be written whole; `hand.missing(in: text)` says which
characters cannot.

## Drawing a hand

Show `HandEditor()` somewhere you can reach it. To keep it to yourself, only
in Debug builds:

```swift
#if DEBUG
.sheet(isPresented: $drawing) { HandEditor() }
#endif
```

1. Draw each character on the ruled square. "keep" moves on; "again" keeps it
   and lets you draw the same character once more (two or three of each stops
   repeated letters looking stamped).
2. The row above the square shows every drawing kept for that character.
   Tap one to set how often the pen uses it: **usual** (the everyday ones,
   picked between evenly), **occasional** (variety, about one time in five)
   or **rare** (a surprise, about one in thirty: an "i" dotted with a heart).
   "forget" removes just that one.
3. Under the square, "ink" and "colour" set the pen's colour, and the three
   short lines beside them set its line: fine, medium or bold. Both are
   chosen stroke by stroke and kept with the stroke (`colors` and `widths`
   in the file), so a letter can be in ink with a red heart, and a picture
   can have a bold outline and fine detail.
4. "try it" writes a sentence with what you have so far.
5. "send my hand as a file" hands `hand.json` to AirDrop, Files or Mail.
6. Add that file to your app target as `hand.json`. `HandStore.shared` finds it.

Letters drawn on the device win over the shipped file, so you see your work
as you go. A hand drawn elsewhere (an iPad and a Pencil) comes in with "use a
hand file".

To match your app's look, pass a `HandStyle` (colours and one typeface):

```swift
var style = HandStyle.journal
style.font = { .custom("SpecialElite-Regular", size: $0) }
HandEditor(style: style)
```

## Signing

A signature is one drawing, a `Glyph` like any letter, but it belongs to a
person and not to a hand: somebody who has never drawn an alphabet can still
sign. `SignaturePad` is the page for it, and it leaves where the signatures
are kept to the app:

```swift
@State private var signatures: [Glyph] = []     // or loaded from your server
@State private var signing = false

// somewhere in body:
.fullScreenCover(isPresented: $signing) {
    SignaturePad(signatures: $signatures)       // adds to, and removes from, the list
}
```

Keep a few (five at most, unless you pass another `limit`) and they are not
all alike. To sign a line, hand the list to the pen:

```swift
Handwriting(text: note, hand: hand, signatures: signatures)
```

The pen writes the line, then signs under it with one of them, slowly. Which
one depends on the text, so the same note is always signed the same way and
the next note probably is not. A note you show in type can be signed too:
give the pen no text and an empty hand, and it writes the signature alone.

```swift
Text(note)
Handwriting(text: "", hand: Hand(), signatures: signatures)
```

`GlyphView(signatures[0])` shows one as a still picture. `Glyph` is `Codable`,
so the list goes to a server as JSON as it is.

The three short lines beside "clear" choose the pen's line: fine, medium or
bold. A signature keeps the line it was signed with.

The demo keeps its signatures in the hand, as a drawing named "signature".

## The font tool

```bash
uv run Tools/hand_font.py my-hand.json -o Hand.ttf --family "My Hand"
```

(`uv` installs fonttools and shapely for the run. Without it: `pip install
fonttools shapely`, then `python3 Tools/hand_font.py ...`.) The tool reads the
pen's sizes out of `Sources/HandKit/Written.swift`, so the font and the pen
agree. A stroke's thickness is kept. Colour is lost: a font is one colour.

## Tests

```bash
swift test
```
