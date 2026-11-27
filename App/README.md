# Handkit, the app

Draw your handwriting, write with it, send what it wrote. One app for iPhone
and iPad, built on the library in this repository and on nothing else: no
account, no server of its own, no third-party code.

```bash
open App/Handkit.xcodeproj
```

Pick an iPhone or an iPad simulator and Run. (Drawing with a mouse in the
simulator works; a real device and a finger, or an iPad and a Pencil, is the
honest test.)

## What is in it

| Page | File | What it is for |
| --- | --- | --- |
| Welcome | `Welcome.swift` | Shown once: what this is, and the way in. |
| Write | `WriteView.swift` | Type a note, watch the pen write it, change the ink, the size and the lean, share the note as a picture. |
| My hand | `HandView.swift` | Every character in a box, drawn or not, with how far along the hand is. Tapping a box opens the drawing page there. The signature is here too. |
| Keep | `KeepView.swift` | Send the hand as a file, bring one in from another device, start over. "Developer tools" is the switch for everything only an app builder needs. |
| Publish | `Publish.swift` | With developer tools on, a part of Keep: send the hand to a server that an app reads its handwriting from. See "Publishing a hand" below. |
| The drawing page | `HandEditor`, in the library | The same page the library gives any app, without the developer's tools unless the switch is on. |

`Main.swift` starts the app and holds the tab bar. `Theme.swift` has the
colors, the type and the few shapes the pages share.

## Publishing a hand

Drawing never sends anything anywhere: the hand is saved on the device as
you draw, and that is all. Publishing is a deliberate act. With developer
tools on, the Keep page has a "Publish" part with two things to fill in:

- **Server**: the address of an API that takes hands, such as
  `ps.example.com`. Only `https` is used, because the key travels with it.
- **Publishing key**: that server's key (for P.S., its `HAND_PUBLISH_KEY`).
  It is kept in the Keychain, on this device only.

"Publish my hand" asks once and then sends the whole hand, as it is at that
moment, with `PUT <server>/api/hand` and `Authorization: Bearer <key>`. The
server keeps every hand it is sent and never changes one; the one sent last
is the one new notes are written in, and notes written before keep the hand
they were written in. Publishing an earlier hand again (bring its file in,
publish) takes a newer one back.

Under the button the page says where things stand: never published,
published and unchanged, or drawn in since. That is worked out on the
device, from a mark of the hand as it was last published from here.

Two things to know before this goes to the store. It is the one place where
the app talks to a server, and only to one the person typed in themselves,
so "nothing is collected" stays true as long as that server is yours. And
it is behind developer tools on purpose: if it ever becomes how anybody
sends their hand to a server you run, the privacy answers in App Store
Connect change with it.

## iPhone and iPad

It is one app (a "universal" app: one binary, one App Store listing), and
each page lays itself out for the room it has.

| | iPhone | iPad |
| --- | --- | --- |
| Write | The sheet above, the note and its buttons below. The pen's settings slide up on a card. | The note and the pen's settings in a column on the left, the sheet on the right. |
| My hand | About six boxes to a row. | As many as fit, in a column that stays readable. |
| The drawing page | One column. | Two: the square and the pen on the left, what has been kept and the page's advice on the right. A larger square, for a Pencil. |
| Turning it | Upright only. | Any way up. In Split View or Slide Over it gets narrow and uses the iPhone's layouts. |

The pages do not ask "is this an iPad?". They ask how wide they are
(`horizontalSizeClass`, or the measured width on the drawing page), which is
why a narrow iPad window gets the phone's layout for free.

## What is not in it yet

- **A font.** `Tools/hand_font.py` makes a `.ttf` from a hand, but it is
  Python and runs on a Mac. In the app it would mean doing the same in Swift.
- **A film of the pen writing.** "Share" sends the finished note as a still
  picture.
- **More than one hand.** `HandStore(name:)` can keep several; the app has
  one.
- **A written welcome.** The welcome page writes its line with the pen if the
  app ships a small hand named `welcome.json`, and sets it in type if not.
  To make one from a hand of your own (only the letters of that one line are
  kept):

  ```bash
  python3 Tools/hand_subset.py my-hand.json "your handwriting, kept" -o App/HandkitApp/welcome.json
  ```

  Xcode picks the file up by itself: everything in `App/HandkitApp` belongs
  to the app.

## The icon

`App/HandkitApp/Assets.xcassets/AppIcon.appiconset/icon.png` is a stand-in
made by `App/Tools/make_icon.py`: the ruled square with an "h" on it. To
replace it with a drawing of your own, turn on "developer tools" on the
Keep page, draw the "app icon" entry on the drawing page, and "send the
icon" hands over a 1024 by 1024 `icon.png` to put in its place.

## Releasing it

The app is a versioned artifact cut by hand, like P.S.: you archive it in
Xcode and upload it, and a script keeps the numbers and the tags straight.
(For a Java person: `mvn release`, with Xcode doing the build.)

**Once, before the first upload:**

1. In [App Store Connect](https://appstoreconnect.apple.com), My Apps > "+"
   > New App. Platform iOS, bundle ID `com.juettner.handkit` (register it
   under Certificates, Identifiers & Profiles first if it is not in the
   list), and a name. "Handkit" may be taken in the store; the name on the
   home screen (`CFBundleDisplayName` in `Info.plist`) does not have to match.
2. The listing needs a privacy policy URL and a support URL. The policy is
   one sentence long and true: nothing is collected. Under App Privacy,
   answer "Data Not Collected".
3. Screenshots: an iPhone set (6.9-inch) and an iPad set (13-inch). Both are
   required because the app runs on both.

**Each release:**

```bash
Tools/release.sh last
```

shows what has reached `main` since the last one. Then:

```bash
Tools/release.sh start
```

(or `Tools/release.sh start 1.1` to change the version as well). It refuses
unless you are on a clean `main` that matches GitHub, adds one to the build
number and commits that on your Mac. In Xcode: choose "Any iOS Device",
Product > Archive, then Distribute App > TestFlight & App Store. Once the
upload has gone through:

```bash
Tools/release.sh finish
```

tags the commit `app-1.0-b1` (version, then build number) and pushes `main`
and the tag. Try the build from TestFlight on a real iPhone and a real iPad
before sending it for review.

The tags P.S. puts on this repository (`ios-1.1-b7`) mark which HandKit a
P.S. build was made against. These start with `app-`, so the two kinds
never meet.

## What has and has not been checked

The app was written without a Mac in reach, so **it has not been compiled or
run**. Expect a first build to turn up a few errors, and the first run to
turn up spacing that wants adjusting. Worth looking at first:

- the drawing page in two columns on an iPad, upright and on its side;
- the Write page with the keyboard up on a small iPhone;
- "Share", then "Save Image", on a device (it asks for permission to add to
  Photos the first time);
- "Open a hand file" after choosing to replace the hand that is there.
