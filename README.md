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

There is an Android library too, in `android/`: the same pen in Kotlin and
Jetpack Compose, reading the same `hand.json`. See "On Android" below.

## What is in it

| | |
| --- | --- |
| `Hand`, `Glyph` | The data. Plain `Codable` JSON: ship it in the app, save it, or send it over a network. |
| `Handwriting` | The view. `Handwriting(text:hand:)` writes a line with the pen. |
| `Written` | The arithmetic behind the view: where each stroke goes and when. No views; testable. |
| `Sketch` | The same drawing, made by the pen while you watch. |
| `GlyphView` | Shows one drawing as a picture, fitted to its frame. For drawings kept under a name (`hand.drawings(named: "envelope")`): pass their names to `HandEditor(drawings:)` and they get a row of their own on the drawing page. |
| `HandStore` | Loads `hand.json` (drawn on this phone if there is one, otherwise the one shipped in the app) and saves what the editor draws. |
| `HandEditor` | The drawing page: draw each character on a ruled square, try a sentence, send the hand as a file. It also asks for the app's icon (the "app icon" entry in the row of pictures): there the square is the icon, and "send the icon" hands over the 1024 x 1024 `icon.png`. `HandEditor(icon: false)` leaves that out. For a picture your app shows very small, `HandEditor(drawings:labels:sizes:)` takes the size in points: the square then has a box of that shape to fill and shows each kept drawing at its real size. `hints:` takes a sentence about a picture (what it is of, where the app shows it), shown under the square while it is drawn. iOS only. |
| `SignaturePad` | The signing page: sign on a line, keep a few. Each is a `Glyph`, and `Handwriting(signatures:)` signs under a line with one of them. iOS only. |
| `Tools/hand_font.py` | Turns a `hand.json` into a real `.ttf`, for text that cannot be drawn stroke by stroke (a text field being typed in). |
| `Tools/hand_svg.py` | Writes one line with the pen and keeps it as an animated `.svg`, for a web page: the strokes are drawn in order, with no script and without publishing the hand. |

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
behind the nib), `mirrored` (written backwards, for a mirror), `weather`
(`.rain` lets the ink run a little down the page, `.sun` dries it pale),
`words` (holds the pen: it writes only that many words and waits for the
number to go up, so an app can release a word for each step taken),
`onWord` (called as the pen starts each word, so an app can keep time with
it) and `onDone`.

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

## On Android

`android/handkit` is the pen as an Android library: Kotlin, Jetpack Compose,
Android 9+. One dependency, Kotlin's own JSON library.

| Swift | Kotlin (`android/handkit/src/main/kotlin/com/juettner/handkit/`) |
| --- | --- |
| `Hand`, `Glyph` | `Hand.kt`: the same two shapes, reading and writing the same JSON |
| `Written`, `Pen` | `Written.kt`: the same arithmetic, the same numbers |
| `Handwriting` | `Handwriting.kt`: `Handwriting(text = "...", hand = hand)`, with the same `mirrored`, `weather`, `words` and `onWord` as the Swift one |
| `GlyphView`, `Sketch` | `GlyphView.kt` |
| `HandStore` | `HandStore.kt`: reads `hand.json` from the app's `assets` |
| `SignaturePad` | `SignaturePad.kt` |
| `HandEditor` | not on Android. Draw the hand on an iPad; the file is the same. |

```kotlin
// Once, in Application.onCreate:
HandStore.start(this)

// In a composable:
val hand = HandStore.shared.active
if (hand != null && hand.covers("good morning, love")) {
    Handwriting(text = "good morning, love", hand = hand, size = 30.dp)
} else {
    Text("good morning, love")   // no hand shipped yet, or a letter is missing
}
```

**The two pens agree.** Which drawing of a letter is used, how it is nudged,
where a line breaks and when each stroke is made all come from a random
number generator seeded with the text, and the generator and the arithmetic
are the same in both languages. So the same text in the same hand comes out
the same on an iPhone and on an Android phone. `Written.swift` and
`Written.kt` must be changed together to keep it so; both say so at the top.

An app adds it by pointing its `settings.gradle.kts` at the folder:

```kotlin
include(":handkit")
project(":handkit").projectDir = file("../../handkit/android/handkit")
```

and its own build supplies the versions of the Android, Compose and
serialization plugins (see `android/build.gradle.kts` for the ones this was
built with).

To build it by itself and run its tests (the Swift tests, ported one for one,
and a check of the generator against numbers worked out independently):

```bash
cd android
```

```bash
./gradlew :handkit:testDebugUnitTest
```

Not yet done: running it on a phone. The tests cover the arithmetic; the
drawing has been looked at in pictures drawn on a build machine (in the P.S.
app's tests), not on a device.

## The font tool

```bash
uv run Tools/hand_font.py my-hand.json -o Hand.ttf --family "My Hand"
```

(`uv` installs fonttools and shapely for the run. Without it: `pip install
fonttools shapely`, then `python3 Tools/hand_font.py ...`.) The tool reads the
pen's sizes out of `Sources/HandKit/Written.swift`, so the font and the pen
agree. (The Android pen keeps its own copy of those numbers, in `Written.kt`.) A stroke's thickness is kept. Colour is lost: a font is one colour.

Only a letter's usual drawings take turns in the font. Occasional and rare
ones are left for the app to ask for (the OpenType features `ss01`, `ss02`
and so on): the pen can use a drawing one time in five, but a font can only
take turns, and a heart meant for now and then would land in every other
word.

## The picture tool

A web page has no pen, but it can play back a line the pen wrote. This does
the pen's arithmetic for one text and saves the result as an SVG picture
whose strokes are drawn one after another, at the pen's pace:

```bash
python3 Tools/hand_svg.py my-hand.json "good morning, love" -o note.svg
```

```html
<img src="note.svg" width="412" height="96" alt="good morning, love">
```

It needs nothing but Python, and the page needs no script: the animation is
a few lines of CSS inside the picture. The picture holds the strokes of that
one line, so the hand file itself is not published. A stroke's colour and
thickness are kept, and so are crossing out, the rare drawings and each
letter's own shade of ink. `"\n"` in the text starts a new line; `--center`,
`--size`, `--ink`, `--seed`, `--plain`, `--slant`, `--delay` and `--speed`
(0 for a line already written) do what they do on `Handwriting`. The file's
own notes say what is lost (it is the same every time it is shown) and how
to show a still line to somebody who has asked for less motion.

## Tests

```bash
swift test
```

For the Android library, see "On Android" above. Its tests also run on
GitHub (`.github/workflows/android.yml`) whenever `android/` or
`Written.swift` changes. The Swift tests do not: they need a Mac.
