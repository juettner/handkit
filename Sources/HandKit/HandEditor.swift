//
//  HandEditor.swift
//
//  "My hand": where you draw your letters.
//
//  One character at a time. The page shows which one, you draw it with a
//  finger on the ruled square, and "keep" saves it and moves to the next.
//  "again" saves it and stays, so you can draw the same letter two or three
//  times; the pen then picks between them and repeated letters stop
//  looking stamped. "try it" writes a sentence with what you have so far.
//
//  The ruled square has four lines, the ones from a school exercise book:
//
//    the tall line    where a "d" or a capital reaches
//    the middle line  the top of an "a" or an "x" (dashed)
//    the line         the baseline, which the letters sit on
//    the tail line    where a "g" or a "y" hangs to
//
//  Three lighter guides help the letters come out the same size, which is
//  most of what makes a line of them look evenly spaced:
//
//    two upright lines  one x-height apart, either side of the middle. An
//                       "n" or an "o" fills the space between them; an "i"
//                       is much narrower, an "m" spills over both.
//    ticks on the line  every half x-height, for judging a width.
//    two pale letters   an "n" you have already drawn, once on each side,
//                       as far from your ink as the pen will really put it.
//                       They move out as the letter grows, so what you see
//                       is the letter between two neighbours on the page.
//
//  Where the letter sits from left to right is not kept: on "keep" the ink
//  is measured from its own left edge to its own right edge, and the pen
//  leaves the same gap (Pen.letterGap) after every letter. So the guides are
//  for size and width, and the pale letters show the gap; none of them can
//  change it.
//
//  How the drawing is captured: a DragGesture reports the finger's position
//  as it moves. Each touch-down to lift-off is one stroke, kept as a list of
//  points. On "keep" the points are converted from the square into
//  x-heights measured from the baseline (see Hand.swift), so the letter
//  can be written at any size later. Nothing is smoothed or corrected here:
//  the wobble is the point.
//
//  Letters you write as one shape ("th", "ff", "ing") can be drawn as one:
//  type them on the "letters you join" line and they join the list. The pen
//  then uses that drawing wherever those letters meet, and falls back to the
//  single letters everywhere else, so the single letters are still needed.
//
//  Above the square is a row of the drawings already kept for the character.
//  Tap one and the line under the row sets how often the pen uses it: usual
//  (the everyday ones, picked between evenly), occasional (variety: about one
//  time in five) or rare (a surprise: about one in thirty, like an "i"
//  dotted with a heart). "forget" removes just that one. The last entry in the list
//  is not a letter at all: "a scribble" is for hearts and doodles, one of
//  which sometimes follows a line.
//
//  The app's icon is drawn here too, as its own thing: "app icon", in the
//  row of pictures. On that entry the square is the icon. What you draw,
//  where you draw it and how thick the line is are what the icon will be,
//  and a pale outline shows the corners iOS cuts off. "keep" it and "send
//  the icon" hands over icon.png, the 1024 by 1024 picture Xcode wants. The
//  drawing is kept in the hand under the name "app-icon" like any other
//  picture, so it travels in hand.json and can be drawn again later.
//
//  The pen can change colour between strokes ("ink" or "colour", with the
//  swatch choosing which colour), and each stroke remembers its own. That is
//  how a letter stays in ink while its heart is red. The icon keeps its
//  colours too.
//
//  It can change its line the same way: the three short lines beside the
//  colour are fine, medium and bold. Each stroke remembers which it was drawn
//  with, so a picture can have a bold outline and fine detail, and a letter
//  drawn bold is written bold. Medium is the pen's usual line (Pen.nib).
//
//  The row along the top jumps to anything: "scribble", then every letter.
//
//  The order puts first what ordinary sentences use most: small letters, then
//  the common punctuation, digits, the rest, capitals, and last the marks a
//  note seldom needs ("@", "+", "#"). A line is only written by hand once
//  every character in it has been drawn, and a capital borrows the small
//  letter until you draw it.
//
//
//  Showing it. It is an ordinary view: push it on a NavigationStack or put
//  it in a sheet. Whether people using your app can reach it is up to you.
//  To keep it to yourself, show it only in Debug builds:
//
//      #if DEBUG
//      .sheet(isPresented: $drawing) { HandEditor() }
//      #endif
//
//  iOS only: it needs a finger (or a Pencil) and UIKit's image renderer.
//

#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The ruled lines, as fractions of the square's side.
private enum Ruling {
    static let baseline: CGFloat = 0.66
    /// One x-height.
    static let unit: CGFloat = 0.27
    static var middle: CGFloat { baseline - unit }
    static var tall: CGFloat { baseline - unit * 1.8 }
    static var tail: CGFloat { baseline + unit * 0.85 }
    /// The two upright guides: one x-height apart, either side of the middle.
    static var left: CGFloat { 0.5 - unit / 2 }
    static var right: CGFloat { 0.5 + unit / 2 }
}

/// A picture the app shows very small (see `sizes` on HandEditor).
private enum SmallPicture {
    /// The longer side of the pale box to fill, as a fraction of the square.
    static let box: CGFloat = 0.8
    /// GlyphView's line is never thinner than this many points, and it leaves
    /// this much of the frame for the drawing. Together they say how thick the
    /// line is against a drawing shown small. Keep them equal to GlyphView's.
    static let line: CGFloat = 1.2
    static let fill: CGFloat = 0.92
}

/// The page with room to spare, in points.
private enum Wide {
    /// The widest the page's column gets, its margins included.
    static let page: CGFloat = 960
    /// The least room, inside the margins, that takes two columns: an iPad
    /// held upright has it, a phone or an iPad sharing its screen does not.
    static let least: CGFloat = 700
    /// Between the two columns.
    static let gap: CGFloat = 40
    /// The least the second column is left with.
    static let side: CGFloat = 300
}

/// The app icon, as fractions of its side.
private enum Icon {
    /// The line: thick, so the icon still reads when it is small.
    static let line: CGFloat = 0.045
    /// How round iOS cuts the corners (near enough; the real shape is a touch squarer).
    static let corner: CGFloat = 0.2237
    /// The picture Xcode wants, in pixels.
    static let pixels: CGFloat = 1024
}

public struct HandEditor: View {
    @Environment(\.dismiss) private var dismiss
    /// Regular means there is room to spare: an iPad, where the square can be larger for a Pencil.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var hands: HandStore
    private let style: HandStyle
    /// The sentence "try it" writes, as far as the letters drawn so far allow.
    private let sample: String
    private let onClose: (() -> Void)?
    /// Named drawings the app wants drawn, listed even before they are.
    private let drawings: [String]
    /// What to call a named drawing on the page, where its name would not do.
    private let labels: [String: String]
    /// The size, in points, at which the app shows a named drawing, for those it shows small.
    private let sizes: [String: CGSize]
    /// What to say about a picture while it is being drawn, by its name.
    private let hints: [String: String]
    /// Whether the page asks for the app's icon.
    private let asksForIcon: Bool
    /// Whether the page has the tools of somebody building an app with the hand.
    private let showsTools: Bool
    /// The character to open at, or nil for the first one not drawn yet.
    private let start: String?

    @State private var index = 0
    /// Finished strokes of the letter being drawn, in fractions of the square.
    @State private var strokes: [[CGPoint]] = []
    /// The colour of each finished stroke, 0xRRGGBB, or -1 for ordinary ink.
    @State private var inks: [Int] = []
    /// Whether the pen is drawing in colour, and which. Chosen per stroke, so
    /// a letter can be in ink with only its heart in red.
    @State private var inColour = false
    @State private var colour: Color
    /// How thick each finished stroke is, as a multiple of the usual line.
    @State private var weights: [Double] = []
    /// The line the pen is drawing with. Chosen per stroke, like the colour.
    @State private var weight = LineWeight.medium
    /// The stroke under the finger.
    @State private var current: [CGPoint] = []
    @State private var trying = false
    /// Changes each time "try it" is tapped, so the sentence is written afresh.
    @State private var tries = 0
    @State private var picking = false
    /// Joined letters named in this visit, kept in the list even before they are drawn.
    @State private var added: Set<String> = []
    /// What is typed on the "letters you join" line.
    @State private var joining = ""
    /// Which of the drawings already kept is picked, in the row above the square.
    @State private var picked: Int? = nil
    /// What is typed on the "a drawing, by name" line.
    @State private var naming = ""
    @State private var fileNote: String? = nil
    /// The icon picture made from a kept drawing of it, once there is one to send.
    @State private var iconURL: URL? = nil

    /// Everything the page asks for, in the order it asks: small letters, the
    /// common punctuation, digits, the rest, capitals, the marks a note seldom
    /// needs (an "@", a "+", a song title's "#"), and last the scribble.
    /// The two backslashes are one: that is how Swift spells a backslash.
    public static let characters: [String] =
        Array("abcdefghijklmnopqrstuvwxyz.,?'!-0123456789\":;()&/ABCDEFGHIJKLMNOPQRSTUVWXYZ@#$%*+=~_<>[]{}|\\^`").map { String($0) }
            + [Hand.scribble]

    /// - Parameters:
    ///   - store: where the drawings are kept. The shared store unless you keep more than one hand.
    ///   - style: the page's colours and typeface.
    ///   - sample: the sentence "try it" writes.
    ///   - drawings: names of pictures your app uses (see `Hand.drawings(named:)`).
    ///     They get a row of their own at the top, waiting to be drawn, with
    ///     hyphens shown as spaces. Left empty, the page has a line for typing a name.
    ///   - labels: what to call a picture in that row, by its name, when the
    ///     name itself reads badly: `["status-wifi": "wifi"]`.
    ///   - sizes: the size in points your app shows a picture at, by its name,
    ///     for pictures shown very small (a status icon of 18 by 12). The
    ///     square then has a pale box of that shape to fill, the pen is as
    ///     thick against the box as the line will be at that size, and each
    ///     kept drawing is shown beside the name at its real size.
    ///   - hints: a sentence or two about a picture, by its name, shown under
    ///     the square while it is being drawn, ahead of the page's own advice:
    ///     what the picture is of and where your app shows it.
    ///   - icon: whether the page asks for the app's icon: an "app icon" entry
    ///     in the row of pictures, where the square is the icon. Turn it off
    ///     if people using your app can reach this page.
    ///   - tools: whether the page has what somebody building an app needs:
    ///     sending the hand as a file and loading one, "by hand" or "typed",
    ///     and pictures kept under a name. An app whose own pages do the
    ///     sending passes false, and the page is only for drawing letters.
    ///     Pictures named in `drawings` are asked for either way.
    ///   - start: the character to open at (one of `characters`, or letters
    ///     already drawn joined). Left out, the page opens at the first
    ///     character not drawn yet.
    ///   - onClose: what "back" does. Left out, it dismisses the page (pops it
    ///     off a NavigationStack, or closes the sheet it was shown in).
    @MainActor
    public init(
        store: HandStore = .shared,
        style: HandStyle = .journal,
        sample: String = "the quick brown fox jumps over the lazy dog",
        drawings: [String] = [],
        labels: [String: String] = [:],
        sizes: [String: CGSize] = [:],
        hints: [String: String] = [:],
        icon: Bool = true,
        tools: Bool = true,
        start: String? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.drawings = drawings
        self.labels = labels
        self.sizes = sizes
        self.hints = hints
        self.asksForIcon = icon
        self.showsTools = tools
        self.start = start
        _hands = ObservedObject(wrappedValue: store)
        self.style = style
        self.sample = sample
        self.onClose = onClose
        _colour = State(initialValue: style.heart)
    }

    /// Everything that can be drawn: the fixed list, then your joined letters,
    /// then the named drawings (their keys sort after every letter).
    private var all: [String] {
        let saved = hands.hand.glyphs.keys.filter { $0.count > 1 }
        // Without the tools, a picture the page was not asked for is not on it
        // (a signature kept in the hand, say), so "skip" never walks into one.
        let extra = Set(saved).union(added).union(asked).filter { showsTools || asked.contains($0) || Hand.drawingName(of: $0) == nil }
        return Self.characters + extra.sorted()
    }
    /// The keys of the pictures the page asks for: the app's, in its order, then the icon.
    private var asked: [String] {
        drawings.map { Hand.drawingKey($0) } + (asksForIcon ? [Hand.drawingKey(Hand.icon)] : [])
    }
    private var character: String { all[min(index, all.count - 1)] }
    private var drawnCount: Int { Self.characters.filter { !(hands.hand.glyphs[$0] ?? []).isEmpty }.count }
    private var timesDrawn: Int { hands.hand.glyphs[character]?.count ?? 0 }
    private func times(_ frequency: Glyph.Frequency) -> Int {
        hands.hand.glyphs[character]?.filter { $0.frequency == frequency }.count ?? 0
    }
    private var isScribble: Bool { character == Hand.scribble }
    /// The name of the picture being drawn, when it is one and not writing.
    private var drawingName: String? { Hand.drawingName(of: character) }
    /// A scribble or a named drawing: any size, anywhere, no guides.
    private var isFreeform: Bool { isScribble || drawingName != nil }
    /// The app's icon: a picture, but one whose place and size in the square are kept.
    private var isIcon: Bool { drawingName == Hand.icon }
    /// The drawing the icon is made from: the one picked in the row, or else
    /// the one kept last. Nil anywhere but on the icon's entry.
    private var iconGlyph: Glyph? {
        guard isIcon, let kept = hands.hand.glyphs[character], !kept.isEmpty else { return nil }
        if let picked, kept.indices.contains(picked) { return kept[picked] }
        return kept.last
    }
    /// What an entry is called on the page: for a drawing, what the app calls
    /// it or else its name with spaces for hyphens; itself otherwise.
    private func label(_ entry: String) -> String {
        guard let name = Hand.drawingName(of: entry) else { return entry }
        return labels[name] ?? name.replacingOccurrences(of: "-", with: " ")
    }
    /// What the app said about the picture being drawn, with a space after it, or nothing.
    private var hint: String {
        guard let name = drawingName, let said = hints[name] else { return "" }
        return said + " "
    }
    /// The size the app shows the picture being drawn at, if it said. Nil for
    /// everything else, and for a size that is not a size.
    private var shownSize: CGSize? {
        guard let size = drawingName.flatMap({ sizes[$0] }), size.width > 0, size.height > 0 else { return nil }
        return size
    }
    /// The pale box to fill when drawing a picture that is shown small, in
    /// fractions of the square: the shape the app shows it in, as large as fits.
    private func smallBox(_ shown: CGSize) -> CGRect {
        let width = min(SmallPicture.box, SmallPicture.box * shown.width / shown.height)
        let height = width * shown.height / shown.width
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
    /// The keys of every picture: the ones the app asked for, in its order, then any others in the hand.
    private var pictures: [String] {
        guard showsTools else { return asked }
        let others = Set(hands.hand.glyphs.keys).union(added).filter { Hand.drawingName(of: $0) != nil && !asked.contains($0) }
        return asked + others.sorted()
    }
    /// "drawn 3 times, 1 of them rare"
    private var drawnNote: String {
        if timesDrawn == 0 { return "not drawn yet" }
        let drawn = timesDrawn == 1 ? "drawn once" : "drawn \(timesDrawn) times"
        let kinds = [(times(.occasional), "occasional"), (times(.rare), "rare")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return ([drawn] + kinds).joined(separator: ", ")
    }
    private var blank: Bool { strokes.isEmpty && current.isEmpty }
    /// A letter already drawn, to show palely either side of the one being
    /// drawn. "n" is the letter type designers space everything against (two
    /// straight sides); failing that an "o", failing that any small letter.
    private var neighbour: Glyph? {
        for key in ["n", "o"] + Self.characters.prefix(26) {
            if let glyph = hands.hand.glyphs[key]?.first(where: { $0.frequency == .usual }) { return glyph }
        }
        return nil
    }

    public var body: some View {
        ZStack {
            style.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Word("back", tone: .grey, size: TypeSize.small) {
                        if let onClose { onClose() } else { dismiss() }
                    }
                    Spacer()
                    Small("\(drawnCount) of \(Self.characters.count) drawn")
                    // Always in reach, at the top: this is how the hand leaves the
                    // device (AirDrop, Files, Mail) to be shipped inside an app.
                    if showsTools {
                    ShareLink(item: hands.fileURL) {
                        Text("send my hand")
                            .font(style.font(TypeSize.small))
                            .foregroundStyle(style.ink)
                            .underline()
                            .frame(minHeight: 44)
                            .padding(.leading, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedStyle())
                    .disabled(hands.hand.isEmpty)
                    .opacity(hands.hand.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Send my hand as a file")
                    }
                }
                .frame(minHeight: 24)

                if trying {
                    trial
                } else {
                    // GeometryReader says how much room there is, which decides
                    // between one column and two. It puts what is inside it at
                    // its top left corner, where the page starts anyway.
                    GeometryReader { room in
                        drawing(width: room.size.width)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            // On a wide screen the page keeps to a column in the middle and does
            // not stretch from edge to edge.
            .frame(maxWidth: Wide.page, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
        }
        // The page's own words are the only chrome; the private views below read the style from here.
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.handStyle, style)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result, hands.use(fileAt: url) {
                fileNote = "Now writing in that hand."
                tries += 1
            } else if case .success = result {
                fileNote = "That file is not a hand."
            }
        }
        // The icon picture follows the drawing it is made from: written when one
        // is kept or another is tapped, gone on leaving the icon's entry.
        // (`initial: true` also runs this once when the page first appears.)
        .onChange(of: iconGlyph, initial: true) { _, glyph in
            iconURL = glyph.flatMap { writeIcon($0) }
        }
        .onAppear {
            // Start where the app asked, or else at the first character that has not been drawn yet.
            if let start, let asked = all.firstIndex(of: start) {
                index = asked
            } else if let first = Self.characters.firstIndex(where: { (hands.hand.glyphs[$0] ?? []).isEmpty }) {
                index = first
            }
        }
    }

    // MARK: - Drawing a letter

    /// The page while drawing. On a phone it is one column, top to bottom. With
    /// room to spare (an iPad, unless it is sharing the screen) it is two: the
    /// square and the pen on the left, and on the right what has been kept and
    /// what the page has to say, so the square does not sit under a tall stack
    /// of rows with half the screen empty beside it.
    private func drawing(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            strip
            if !pictures.isEmpty {
                pictureRow
            }
            if width >= Wide.least {
                HStack(alignment: .top, spacing: Wide.gap) {
                    VStack(alignment: .leading, spacing: 0) {
                        titleRow
                        ruledSquare
                            .padding(.top, 8)
                        keepRow
                        penRow
                        moveRow
                    }
                    // As wide as the square wants to be, less if the other column would be squeezed.
                    .frame(width: min(squareSide, width - Wide.gap - Wide.side))
                    VStack(alignment: .leading, spacing: 0) {
                        Small("kept so far")
                            .frame(minHeight: 44)
                        previous
                        pickedLine
                        iconRow
                        advice
                        joinRow
                        nameRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 8)
            } else {
                titleRow
                previous
                pickedLine
                ruledSquare
                    .padding(.top, 8)
                keepRow
                penRow
                moveRow
                iconRow
                advice
                joinRow
                nameRow
            }
        }
    }

    /// How wide the square is when there is room: large for a picture or a
    /// scribble, smaller for a letter or a number, where a big square made the
    /// hand write bigger than it naturally does.
    private var squareSide: CGFloat {
        sizeClass == .regular ? (isFreeform ? 520 : 364) : 300
    }

    /// What is being drawn, how often it has been, and forgetting all of it.
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(isScribble ? "a scribble" : label(character))
                .font(style.font(isFreeform ? TypeSize.body : TypeSize.question))
                .foregroundStyle(style.ink)
            // The last drawing kept (or the one picked), at the size the app shows it.
            if let shownSize, let kept = hands.hand.glyphs[character], let glyph = picked.flatMap({ kept.indices.contains($0) ? kept[$0] : nil }) ?? kept.last {
                GlyphView(glyph, ink: style.ink)
                    .frame(width: shownSize.width, height: shownSize.height)
                    .accessibilityLabel("This drawing at the size the app shows it")
            }
            Small(drawnNote)
            Spacer()
            // Always there, dimmed until there is something to forget, so the
            // square below never moves between one drawing and the next.
            Word("forget", tone: .grey, disabled: timesDrawn == 0, size: TypeSize.small) { hands.forget(character) }
                .accessibilityLabel("Forget every drawing of this character")
        }
    }

    private var keepRow: some View {
        HStack(spacing: 24) {
            Word("keep", disabled: blank) { keep(advance: true) }
                .accessibilityLabel("Keep this drawing and go to the next character")
            Word("again", disabled: blank) { keep(advance: false) }
                .accessibilityLabel("Keep this drawing and draw the same character once more")
            Word("clear", tone: .grey, disabled: blank) { strokes = []; inks = []; weights = []; current = [] }
            Spacer()
        }
        .padding(.top, 8)
    }

    /// The pen's color, chosen stroke by stroke: draw the stem of an "i" in
    /// ink, switch to color, and draw the heart. ColorPicker is the system's
    /// color chooser; the round swatch opens it.
    private var penRow: some View {
        HStack(spacing: 24) {
            Small("pen")
            Word("ink", tone: inColour ? .faint : .ink, marked: !inColour) { inColour = false }
                .accessibilityLabel("Draw the next strokes in ink")
            Word("color", tone: inColour ? .ink : .faint, marked: inColour) { inColour = true }
                .accessibilityLabel("Draw the next strokes in color")
            ColorPicker("Pen color", selection: $colour, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: colour) { inColour = true }
            Spacer()
            // The pen's line, chosen stroke by stroke like its color.
            LineChoice(weight: $weight)
        }
    }

    private var moveRow: some View {
        HStack(spacing: 24) {
            Word("before", tone: .grey) { move(-1) }
                .accessibilityLabel("Previous character")
            Word("skip", tone: .grey) { move(1) }
                .accessibilityLabel("Next character, without saving")
            Spacer()
            Word("try it", tone: .grey, disabled: hands.hand.isEmpty) {
                tries += 1
                trying = true
            }
        }
    }

    /// The app's icon is a picture file, not something drawn while the app
    /// runs, so a kept drawing of it is turned into that picture and sent
    /// from here. The word is always there on the icon's entry, dimmed until
    /// a drawing is kept: a row that came and went would move the page under
    /// the pen.
    @ViewBuilder
    private var iconRow: some View {
        if isIcon {
            HStack(spacing: 24) {
                if let iconURL {
                    ShareLink(item: iconURL) {
                        Text("send the icon")
                            .font(style.font(TypeSize.word))
                            .foregroundStyle(style.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedStyle())
                    .accessibilityLabel("Send the icon as a picture")
                } else {
                    Word("send the icon", tone: .grey, disabled: true) {}
                }
                Spacer()
            }
        }
    }

    /// What the app says about this picture, if anything, then the page's own advice.
    private var advice: some View {
        Small(hint + (isIcon
            ? "The app's icon. The square is the icon: what you draw, where you draw it, as thick as you see it. The pale outline is where the corners are cut off. Keep it, then send the icon; it replaces icon.png in the app's AppIcon.appiconset. Keep more than one and the one you tap in the row is the one sent."
            : shownSize != nil
            ? "A picture the app shows small: about \(Int(shownSize?.width ?? 0)) by \(Int(shownSize?.height ?? 0)) points. Fill the pale box, with few strokes and clear gaps between them. The pen is as thick here, against the box, as the line will be there. Once kept, it is shown beside its name at its real size: if you cannot read it there, forget it and draw it simpler."
            : drawingName != nil
            ? "A picture, not writing: draw it any size, anywhere in the square. Change the pen's color or its line for part of it. Draw it more than once with again and the app can vary them."
            : isScribble
            ? "A heart, a star, anything. Now and then one follows a line. Draw a few with again; the size you draw it is the size it gets."
            : "Draw it the way you write it, sitting on the line. Draw it two or three times with again, so repeated letters do not look stamped. Tap a kept drawing to make it occasional or rare, like a heart for a dot."))
            .padding(.top, 8)
    }

    /// Letters written as one shape. Name them here, then draw them like any other.
    private var joinRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            Small("letters you join")
            Line(placeholder: "th", text: $joining, size: TypeSize.word, capitalization: .never, autocorrect: false, onSubmit: join)
                .frame(width: 72)
                .accessibilityLabel("Letters you write joined")
            Word("draw", tone: .grey, disabled: joining.trimmingCharacters(in: .whitespaces).count < 2, action: join)
                .accessibilityLabel("Draw these joined letters")
        }
    }

    /// A picture the app shows by name. An app that says which pictures it
    /// uses (the `drawings` parameter) has them in the row at the top, and
    /// this line is left out: typing a name is one more thing to get wrong.
    /// It is one of the tools, so a page without them leaves it out too.
    @ViewBuilder
    private var nameRow: some View {
        if drawings.isEmpty && showsTools {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Small("a drawing, by name")
                Line(placeholder: "envelope", text: $naming, size: TypeSize.word, capitalization: .never, autocorrect: false, onSubmit: name)
                    .frame(width: 150)
                    .accessibilityLabel("The name of a drawing")
                Word("draw", tone: .grey, disabled: naming.trimmingCharacters(in: .whitespaces).isEmpty, action: name)
                    .accessibilityLabel("Draw a picture with this name")
            }
        }
    }

    /// The pictures the app uses, by name, always in view like the alphabet
    /// above them: ink is where you are, dark grey has been drawn, pale grey
    /// has not. Nobody has to type a name and get it right.
    private var pictureRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(pictures, id: \.self) { entry in
                    Button { go(to: entry) } label: {
                        Text(label(entry))
                            .font(style.font(TypeSize.small))
                            .foregroundStyle(entry == character ? style.ink : hasDrawing(entry) ? style.muted : style.faint)
                            .underline(entry == character, color: style.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedStyle())
                    .accessibilityLabel("Draw \(label(entry))")
                }
            }
        }
    }

    /// How tall the row of drawings already kept is.
    private static let thumb: CGFloat = 56

    /// The drawings already kept for this character, small, in the order they
    /// were drawn: what the pen will pick between. Tap one to pick it, and
    /// "forget this one" removes just that drawing. The row keeps its height
    /// when it is empty, so the square below never moves under the pen.
    private var previous: some View {
        let kept = hands.hand.glyphs[character] ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(kept.enumerated()), id: \.offset) { number, glyph in
                    Button { picked = picked == number ? nil : number } label: {
                        thumbnail(glyph)
                            .frame(width: thumbWidth(glyph), height: Self.thumb)
                            .overlay(Rectangle().stroke(picked == number ? style.ink : style.edge, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                if glyph.frequency != .usual {
                                    Text(glyph.frequency.rawValue)
                                        .font(style.font(9))
                                        .foregroundStyle(style.grey)
                                        .padding(2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedStyle())
                    .accessibilityLabel("Drawing \(number + 1) of \(label(character))\(glyph.frequency == .usual ? "" : ", \(glyph.frequency.rawValue)")")
                    .accessibilityAddTraits(picked == number ? .isSelected : [])
                }
            }
        }
        .frame(height: Self.thumb)
        .padding(.top, 4)
        // Another character has other drawings: nothing of this one is picked there.
        .onChange(of: character) { picked = nil }
    }

    /// What can be done with the picked drawing: how often the pen uses it,
    /// and forgetting it. Always there, dimmed until a drawing is picked, so
    /// nothing below moves. A scribble or a picture has no "how often".
    private var pickedLine: some View {
        let kept = hands.hand.glyphs[character] ?? []
        let chosen = picked.flatMap { kept.indices.contains($0) ? $0 : nil }
        let now = chosen.map { kept[$0].frequency }
        return HStack(spacing: 20) {
            Small(chosen == nil ? "tap a drawing" : "this one is")
            if !isFreeform {
                ForEach(Glyph.Frequency.allCases, id: \.self) { frequency in
                    Word(frequency.rawValue, tone: now == frequency ? .ink : .grey, marked: now == frequency, disabled: chosen == nil, size: TypeSize.small) {
                        if let chosen { hands.setFrequency(frequency, at: chosen, for: character) }
                    }
                    .accessibilityLabel("Use this drawing: \(frequency.rawValue)")
                }
            }
            Spacer()
            Word("forget", tone: .grey, disabled: chosen == nil, size: TypeSize.small) {
                if let chosen { hands.remove(at: chosen, for: character) }
                picked = nil
            }
            .accessibilityLabel("Forget this one drawing")
        }
    }

    private func thumbWidth(_ glyph: Glyph) -> CGFloat {
        isFreeform ? Self.thumb : max(40, CGFloat(glyph.advance) * Ruling.unit * Self.thumb + 16)
    }

    /// One kept drawing, small. A letter is shown sitting on its line, at the
    /// size it has against the ruling, so a comma looks like a comma and not
    /// like a letter-sized blob. A picture or a scribble fills the box.
    @ViewBuilder
    private func thumbnail(_ glyph: Glyph) -> some View {
        if isIcon {
            // The icon as it will be: placed as drawn, corners cut.
            Canvas { graphics, size in
                drawIcon(glyph, side: size.width) { path, color, line in
                    graphics.stroke(path, with: .color(color), style: line)
                }
            }
            .background(style.paper)
            .clipShape(RoundedRectangle(cornerRadius: Icon.corner * Self.thumb, style: .continuous))
        } else if isFreeform {
            GlyphView(glyph, ink: style.ink)
                .padding(4)
        } else {
            Canvas { graphics, size in
                let unit = Ruling.unit * size.height
                let base = Ruling.baseline * size.height
                var line = Path()
                line.move(to: CGPoint(x: 0, y: base))
                line.addLine(to: CGPoint(x: size.width, y: base))
                graphics.stroke(line, with: .color(style.rule), lineWidth: 1)

                let left = (size.width - CGFloat(glyph.advance) * unit) / 2
                for (number, stroke) in glyph.points.enumerated() where !stroke.isEmpty {
                    let placed = stroke.map { CGPoint(x: left + $0.x * unit, y: base + $0.y * unit) }
                    graphics.stroke(
                        Written.smooth(placed),
                        with: .color(glyph.color(of: number) ?? style.ink),
                        style: StrokeStyle(lineWidth: max(1, Pen.nib * unit * glyph.width(of: number)), lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }

    /// Everything that can be drawn, in one row, to jump straight to any of it:
    /// "scribble" first, where it cannot be missed, then the letters in a row
    /// that scrolls sideways. Ink is where you are, dark grey has been drawn,
    /// pale grey has not. Walking there with "skip" took seventy taps.
    private var strip: some View {
        HStack(spacing: 16) {
            Word("scribble", tone: isScribble ? .ink : .grey, marked: isScribble, size: TypeSize.small) { go(to: Hand.scribble) }
                .accessibilityLabel("Draw a heart or a scribble")
            // ScrollViewReader hands out a `proxy` that can scroll the row to an
            // entry by its id, which keeps the current letter in view.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        // Pictures have their own row, below.
                        ForEach(all.filter { $0 != Hand.scribble && Hand.drawingName(of: $0) == nil }, id: \.self) { entry in
                            Button { go(to: entry) } label: {
                                Text(label(entry))
                                    .font(style.font(TypeSize.body))
                                    .padding(.horizontal, entry.count > 1 ? 8 : 0)
                                    .foregroundStyle(entry == character ? style.ink : hasDrawing(entry) ? style.muted : style.faint)
                                    .underline(entry == character, color: style.ink)
                                    .frame(minWidth: 30, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressedStyle())
                            .id(entry)
                            .accessibilityLabel("Draw \(label(entry))")
                        }
                    }
                }
                .onChange(of: character) { withAnimation { proxy.scrollTo(character, anchor: .center) } }
                .onAppear { proxy.scrollTo(character, anchor: .center) }
            }
        }
    }

    private func hasDrawing(_ entry: String) -> Bool { !(hands.hand.glyphs[entry] ?? []).isEmpty }

    /// Jumps to one entry, with an empty square.
    private func go(to entry: String) {
        strokes = []
        inks = []
        weights = []
        current = []
        index = all.firstIndex(of: entry) ?? index
    }

    /// The square you draw in: the ruled lines, what has been drawn, and the gesture that draws.
    private var ruledSquare: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            Canvas { graphics, size in
                let s = size.width
                // An icon is not written on lines: its square shows the shape iOS
                // cuts it to, and a small cross at the middle to centre against.
                let rules: [(y: CGFloat, color: Color, dash: [CGFloat])] = isIcon ? [] : [
                    (Ruling.tall, style.rule, []),
                    (Ruling.middle, style.faint, [4, 6]),
                    (Ruling.baseline, style.grey, []),
                    (Ruling.tail, style.rule, []),
                ]
                if isIcon {
                    let edge = Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s), cornerRadius: Icon.corner * s, style: .continuous)
                    graphics.stroke(edge, with: .color(style.faint), lineWidth: 1)
                    var cross = Path()
                    cross.move(to: CGPoint(x: s / 2 - 8, y: s / 2))
                    cross.addLine(to: CGPoint(x: s / 2 + 8, y: s / 2))
                    cross.move(to: CGPoint(x: s / 2, y: s / 2 - 8))
                    cross.addLine(to: CGPoint(x: s / 2, y: s / 2 + 8))
                    graphics.stroke(cross, with: .color(style.faint), lineWidth: 1)
                }
                for rule in rules {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: rule.y * s))
                    path.addLine(to: CGPoint(x: s, y: rule.y * s))
                    graphics.stroke(path, with: .color(rule.color), style: StrokeStyle(lineWidth: 1, dash: rule.dash))
                }

                // A picture shown small: the pale box is the frame the app shows it in.
                if let shownSize {
                    let box = smallBox(shownSize)
                    let edge = Path(CGRect(x: box.minX * s, y: box.minY * s, width: box.width * s, height: box.height * s))
                    graphics.stroke(edge, with: .color(style.faint), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                }

                // The pen is as thick here, against the ruling, as it will be on the
                // page; on the icon's square, as thick as it will be on the icon.
                // For a picture shown small the line cannot shrink with it (it
                // would vanish), so against the box it is thicker than a letter's.
                let letterNib = Pen.nib * Ruling.unit * s
                let smallNib = shownSize.map { SmallPicture.line * smallBox($0).width * s / ($0.width * SmallPicture.fill) } ?? 0
                // This is the usual line: a stroke drawn fine or bold is a multiple of it.
                let nib = isIcon ? Icon.line * s : max(letterNib, smallNib)

                // The lighter guides are for letters. A scribble or a picture is any size, anywhere.
                if !isFreeform {
                    // Two uprights one x-height apart. Joined letters are wider
                    // than that by nature, so they go without.
                    if character.count == 1 {
                        for x in [Ruling.left, Ruling.right] {
                            var path = Path()
                            path.move(to: CGPoint(x: x * s, y: Ruling.tall * s))
                            path.addLine(to: CGPoint(x: x * s, y: Ruling.tail * s))
                            graphics.stroke(path, with: .color(style.rule), lineWidth: 1)
                        }
                    }
                    // A tick under the line every half x-height, out from the middle.
                    for step in -3...3 {
                        let x = (0.5 + CGFloat(step) * Ruling.unit / 2) * s
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: Ruling.baseline * s))
                        path.addLine(to: CGPoint(x: x, y: Ruling.baseline * s + 5))
                        graphics.stroke(path, with: .color(style.faint), lineWidth: 1)
                    }
                    // The pale neighbours, placed as the pen will place them: one
                    // letter gap from the edges of the ink. Only finished strokes
                    // count, so nothing moves while the finger is down. Before the
                    // first stroke they stand outside the two uprights.
                    if let neighbour {
                        let drawn = strokes.flatMap { $0 }.map(\.x)
                        let gap = Pen.letterGap * Ruling.unit
                        let width = CGFloat(neighbour.advance) * Ruling.unit
                        let origins = [
                            (drawn.min() ?? Ruling.left) - gap - width,
                            (drawn.max() ?? Ruling.right) + gap,
                        ]
                        for origin in origins {
                            for (number, stroke) in neighbour.points.enumerated() where !stroke.isEmpty {
                                let placed = stroke.map {
                                    CGPoint(x: (origin + $0.x * Ruling.unit) * s, y: (Ruling.baseline + $0.y * Ruling.unit) * s)
                                }
                                graphics.stroke(
                                    Written.smooth(placed),
                                    with: .color(style.edge),
                                    style: StrokeStyle(lineWidth: nib * neighbour.width(of: number), lineCap: .round, lineJoin: .round)
                                )
                            }
                        }
                    }
                }
                for (number, stroke) in (strokes + [current]).enumerated() where !stroke.isEmpty {
                    let scaled = stroke.map { CGPoint(x: $0.x * s, y: $0.y * s) }
                    // Finished strokes keep the colour and the line they were drawn
                    // with; the one under the finger shows the pen as it is now.
                    let shade: Color = number < strokes.count ? strokeColor(number) : (inColour ? colour : style.ink)
                    let thick = weights.indices.contains(number) ? CGFloat(weights[number]) : weight.rawValue
                    graphics.stroke(
                        Written.smooth(scaled),
                        with: .color(shade),
                        style: StrokeStyle(lineWidth: nib * thick, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = CGPoint(x: value.location.x / side, y: value.location.y / side)
                        // Skip points that have barely moved: they add noise, not shape.
                        if let last = current.last, hypot(point.x - last.x, point.y - last.y) * side < 1.5 { return }
                        current.append(point)
                    }
                    .onEnded { _ in
                        if !current.isEmpty {
                            strokes.append(current)
                            inks.append(inColour ? colour.hex : -1)
                            weights.append(Double(weight.rawValue))
                        }
                        current = []
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: squareSide)
        .overlay(Rectangle().stroke(style.edge, lineWidth: 1))
        .accessibilityLabel("Drawing square for \(label(character))")
    }

    /// The colour a finished stroke in the square was drawn in.
    private func strokeColor(_ number: Int) -> Color {
        inks.indices.contains(number) && inks[number] >= 0 ? Color(hex: UInt32(inks[number])) : style.ink
    }

    /// Saves what is in the square as one drawing of the current character.
    private func keep(advance: Bool) {
        let points = strokes.flatMap { $0 }
        guard let inkLeft = points.map(\.x).min(), let right = points.map(\.x).max() else { return }
        // A letter is measured from its own left edge, so where it sat in the
        // square is forgotten. The icon is measured from the square's edge:
        // where it sits is part of the drawing.
        let left = isIcon ? 0 : inkLeft
        func rounded(_ value: CGFloat) -> Double { (Double(value) * 1000).rounded() / 1000 }
        let flat = strokes.map { stroke in
            stroke.flatMap { [rounded(($0.x - left) / Ruling.unit), rounded(($0.y - Ruling.baseline) / Ruling.unit)] }
        }
        let glyph = Glyph(
            strokes: flat,
            advance: max(0.12, rounded((right - inkLeft) / Ruling.unit)),
            colors: inks.contains { $0 >= 0 } ? inks : nil,
            widths: weights.contains { $0 != 1 } ? weights : nil
        )
        hands.add(glyph, for: character)
        Haptic.success()
        strokes = []
        inks = []
        weights = []
        current = []
        // The icon stays where it is on "keep": the next thing to do is send it.
        if advance && !isIcon {
            move(1)
        } else {
            // The drawing just kept is picked, so "occasional" or "rare" is one tap away.
            picked = (hands.hand.glyphs[character]?.count ?? 1) - 1
        }
    }

    /// Draws a kept icon in a square of the given side, exactly as it was
    /// drawn in the editor's square: same place, same size, same thickness.
    /// `keep` stored the points in x-heights from the square's left edge and
    /// the baseline; this turns them back into fractions of the square. The
    /// caller does the stroking, so the row of small ones (a SwiftUI Canvas)
    /// and the picture file (Core Graphics) share the one layout.
    private func drawIcon(_ glyph: Glyph, side: CGFloat, stroke: (Path, Color, StrokeStyle) -> Void) {
        for (number, points) in glyph.points.enumerated() where !points.isEmpty {
            let line = StrokeStyle(lineWidth: Icon.line * side * glyph.width(of: number), lineCap: .round, lineJoin: .round)
            let placed = points.map {
                CGPoint(x: $0.x * Ruling.unit * side, y: (Ruling.baseline + $0.y * Ruling.unit) * side)
            }
            stroke(Written.smooth(placed), glyph.color(of: number) ?? style.ink, line)
        }
    }

    /// Writes a kept icon drawing as the picture Xcode wants: a 1024 by 1024
    /// PNG, the page's paper behind it, each stroke in its own colour. Saved as
    /// icon.png, so it can replace the file of that name in the app's
    /// AppIcon.appiconset as it is. The corners are left square: iOS cuts them.
    private func writeIcon(_ glyph: Glyph) -> URL? {
        // An icon may not be see-through, and must be exactly this many pixels.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let size = CGSize(width: Icon.pixels, height: Icon.pixels)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(style.paper).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let pen = context.cgContext
            pen.setLineCap(.round)
            pen.setLineJoin(.round)
            drawIcon(glyph, side: Icon.pixels) { path, color, line in
                pen.setLineWidth(line.lineWidth)
                pen.setStrokeColor(UIColor(color).cgColor)
                pen.addPath(path.cgPath)
                pen.strokePath()
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("icon.png")
        guard let data = image.pngData(), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    /// Adds the letters typed on the line to the list and goes to them.
    private func join() {
        let letters = String(joining.filter { !$0.isWhitespace }.map { Hand.plain($0) }.joined().prefix(4))
        guard letters.count > 1 else { return }
        added.insert(letters)
        joining = ""
        strokes = []
        inks = []
        weights = []
        current = []
        index = all.firstIndex(of: letters) ?? index
    }

    /// Adds the name typed on the line to the list, as a picture, and goes to it.
    /// Names are kept simple (small letters, digits, hyphens) so an app can ask for one without surprises.
    private func name() {
        let typed = naming.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !typed.isEmpty else { return }
        let key = Hand.drawingKey(String(typed.prefix(32)))
        added.insert(key)
        naming = ""
        strokes = []
        inks = []
        weights = []
        current = []
        index = all.firstIndex(of: key) ?? index
    }

    private func move(_ step: Int) {
        strokes = []
        inks = []
        weights = []
        current = []
        index = (min(index, all.count - 1) + step + all.count) % all.count
    }

    // MARK: - Trying it

    /// A sentence written with the letters drawn so far, and the two settings.
    private var trial: some View {
        // Only the words that can be written whole.
        let words = sample.split(separator: " ").filter { hands.hand.covers(String($0)) }
        return VStack(alignment: .leading, spacing: 0) {
            Spacer()
            if words.isEmpty {
                Small("Draw a few more letters first.")
            } else {
                // A new seed each time, so writing it again shows the rare drawings and scribbles turning up.
                Handwriting(text: words.joined(separator: " "), hand: hands.hand, ink: style.ink, seed: tries)
                    .id(tries)
            }
            Spacer()

            HStack(spacing: 24) {
                Word("write it again", tone: .grey) { tries += 1 }
                Word("more letters") { trying = false }
            }
            if showsTools {
            HStack(spacing: 24) {
                Word("by hand", tone: hands.enabled ? .ink : .faint, marked: hands.enabled) { hands.enabled = true }
                    .accessibilityLabel("Write in my hand")
                Word("typed", tone: hands.enabled ? .faint : .ink, marked: !hands.enabled) { hands.enabled = false }
                    .accessibilityLabel("Show typed text instead")
            }
            // Hands the saved strokes to AirDrop, Files or Mail, so the hand can be
            // shipped inside an app as hand.json.
            ShareLink(item: hands.fileURL) {
                Text("send my hand as a file")
                    .font(style.font(TypeSize.word))
                    .foregroundStyle(style.muted)
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressedStyle())
            // The other direction: letters drawn elsewhere (an iPad and a Pencil,
            // say) arrive as that same file and replace the hand on this phone.
            Word("use a hand file", tone: .grey) { picking = true }
            if let fileNote {
                Small(fileNote)
            }
            }
            Spacer().frame(height: 24)
        }
    }
}

// MARK: - The pages' own small views
//
// Shared with SignaturePad. They are internal (no `public`), so an app never
// sees them and they cannot clash with an app's views of the same name. They
// read the style from the environment, which each page sets.

private struct HandStyleKey: EnvironmentKey {
    static let defaultValue = HandStyle.journal
}

extension EnvironmentValues {
    var handStyle: HandStyle {
        get { self[HandStyleKey.self] }
        set { self[HandStyleKey.self] = newValue }
    }
}

enum TypeSize {
    static let question: CGFloat = 30
    static let body: CGFloat = 19
    static let word: CGFloat = 15
    static let small: CGFloat = 13
}

enum WordTone {
    case ink, grey, faint
}

/// A word you can tap. The page has no buttons: actions are words.
struct Word: View {
    @Environment(\.handStyle) private var style
    let title: String
    var tone: WordTone = .ink
    var marked = false
    var disabled = false
    var size: CGFloat = TypeSize.word
    let action: () -> Void

    init(_ title: String, tone: WordTone = .ink, marked: Bool = false, disabled: Bool = false, size: CGFloat = TypeSize.word, action: @escaping () -> Void) {
        self.title = title
        self.tone = tone
        self.marked = marked
        self.disabled = disabled
        self.size = size
        self.action = action
    }

    private var color: Color {
        switch tone {
        case .ink: return style.ink
        case .grey: return style.muted
        case .faint: return style.faint
        }
    }

    var body: some View {
        Button {
            Haptic.tick()
            action()
        } label: {
            Text(title)
                .font(style.font(size))
                .foregroundStyle(color)
                .underline(marked, color: style.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityAddTraits(marked ? .isSelected : [])
    }
}

/// The lines the pen can draw with, as multiples of its usual one (Pen.nib).
/// The number is what is kept with each stroke (`Glyph.widths`).
enum LineWeight: CGFloat, CaseIterable {
    case fine = 0.55
    case medium = 1
    case bold = 1.8

    var name: String {
        switch self {
        case .fine: return "fine"
        case .medium: return "medium"
        case .bold: return "bold"
        }
    }

    /// How thick the short line that stands for it is drawn, in points.
    var sample: CGFloat {
        switch self {
        case .fine: return 2
        case .medium: return 4.5
        case .bold: return 9
        }
    }
}

/// Choosing the pen's line: three short lines, each as thick (in proportion)
/// as the line it picks. The one in ink is the pen's; the others are pale.
/// They are pictures and not words because a line shows its own thickness
/// better than "medium" does, and three words would not fit beside the colour
/// on a phone. A screen reader hears the words.
struct LineChoice: View {
    @Environment(\.handStyle) private var style
    /// A Binding: this view reads the pen's line and sets it, but the page owns it.
    @Binding var weight: LineWeight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LineWeight.allCases, id: \.self) { choice in
                Button {
                    Haptic.tick()
                    weight = choice
                } label: {
                    // Capsule is a line with round ends, like the pen's.
                    Capsule()
                        .fill(weight == choice ? style.ink : style.faint)
                        .frame(width: 22, height: choice.sample)
                        // The line is small; the place to tap is not.
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressedStyle())
                .accessibilityLabel("Draw the next strokes with a \(choice.name) line")
                .accessibilityAddTraits(weight == choice ? .isSelected : [])
            }
        }
    }
}

/// Small grey text: a count, a hint.
struct Small: View {
    @Environment(\.handStyle) private var style
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(style.font(TypeSize.small))
            .foregroundStyle(style.grey)
            .lineSpacing(TypeSize.small * 0.3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A line to write on: a text field with nothing but a rule underneath.
private struct Line: View {
    @Environment(\.handStyle) private var style
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = TypeSize.body
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect = true
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 2) {
            TextField("", text: $text, prompt: Text(placeholder).font(style.font(size)).foregroundColor(style.faint))
                .font(style.font(size))
                .foregroundStyle(style.ink)
                .tint(style.ink)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrect)
                .submitLabel(.done)
                .onSubmit { onSubmit?() }
                .padding(.vertical, 6)
                .frame(minHeight: 44)
            Rectangle()
                .fill(style.ink)
                .frame(height: 1)
        }
    }
}

/// Dims a word while the finger is on it. No background, no shape: it is just a word.
struct PressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private extension Color {
    /// The colour as 0xRRGGBB, for saving a pen colour with a drawing.
    var hex: Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func part(_ value: CGFloat) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return part(red) << 16 | part(green) << 8 | part(blue)
    }
}
#endif
