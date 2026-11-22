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
//  "rarely" keeps a drawing as a rare one: the pen uses it only now and then
//  in place of the usual drawings of that letter. The last entry in the list
//  is not a letter at all: "a scribble" is for hearts and doodles, one of
//  which sometimes follows a line.
//
//  The scribble entry can also make the app's icon: draw a heart, tap "make
//  an icon of this", and send the picture to the Mac.
//
//  The pen can change colour between strokes ("ink" or "colour", with the
//  swatch choosing which colour), and each stroke remembers its own. That is
//  how a letter stays in ink while its heart is red. The icon picture keeps
//  the colours too.
//
//  The row along the top jumps to anything: "scribble", then every letter.
//
//  The order puts first what ordinary sentences use most: small letters, then
//  the common punctuation, digits, the rest, and capitals last. A line is
//  only written by hand once every character in it has been drawn, and a
//  capital borrows the small letter until you draw it.
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

    @State private var index = 0
    /// Finished strokes of the letter being drawn, in fractions of the square.
    @State private var strokes: [[CGPoint]] = []
    /// The colour of each finished stroke, 0xRRGGBB, or -1 for ordinary ink.
    @State private var inks: [Int] = []
    /// Whether the pen is drawing in colour, and which. Chosen per stroke, so
    /// a letter can be in ink with only its heart in red.
    @State private var inColour = false
    @State private var colour: Color
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
    /// The icon picture made from the square, once there is one to send.
    @State private var iconURL: URL? = nil

    /// Everything the page asks for, in the order it asks: small letters, the
    /// common punctuation, digits, the rest, capitals, and last the scribble.
    public static let characters: [String] =
        Array("abcdefghijklmnopqrstuvwxyz.,?'!-0123456789\":;()&/ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }
            + [Hand.scribble]

    /// - Parameters:
    ///   - store: where the drawings are kept. The shared store unless you keep more than one hand.
    ///   - style: the page's colours and typeface.
    ///   - sample: the sentence "try it" writes.
    ///   - drawings: names of pictures your app uses (see `Hand.drawings(named:)`),
    ///     so they are in the list waiting to be drawn. Any name can also be
    ///     typed on the page itself.
    ///   - onClose: what "back" does. Left out, it dismisses the page (pops it
    ///     off a NavigationStack, or closes the sheet it was shown in).
    @MainActor
    public init(
        store: HandStore = .shared,
        style: HandStyle = .journal,
        sample: String = "the quick brown fox jumps over the lazy dog",
        drawings: [String] = [],
        onClose: (() -> Void)? = nil
    ) {
        self.drawings = drawings
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
        return Self.characters + Set(saved).union(added).union(drawings.map { Hand.drawingKey($0) }).sorted()
    }
    private var character: String { all[min(index, all.count - 1)] }
    private var drawnCount: Int { Self.characters.filter { !(hands.hand.glyphs[$0] ?? []).isEmpty }.count }
    private var timesDrawn: Int { hands.hand.glyphs[character]?.count ?? 0 }
    private var timesRare: Int { hands.hand.glyphs[character]?.filter(\.isRare).count ?? 0 }
    private var isScribble: Bool { character == Hand.scribble }
    /// The name of the picture being drawn, when it is one and not writing.
    private var drawingName: String? { Hand.drawingName(of: character) }
    /// A scribble or a named drawing: any size, anywhere, no guides.
    private var isFreeform: Bool { isScribble || drawingName != nil }
    /// What an entry is called on the page: its name for a drawing, itself otherwise.
    private func label(_ entry: String) -> String { Hand.drawingName(of: entry) ?? entry }
    /// "drawn 3 times, 1 of them rare"
    private var drawnNote: String {
        if timesDrawn == 0 { return "not drawn yet" }
        let drawn = timesDrawn == 1 ? "drawn once" : "drawn \(timesDrawn) times"
        return timesRare == 0 ? drawn : "\(drawn), \(timesRare) rare"
    }
    private var blank: Bool { strokes.isEmpty && current.isEmpty }
    /// A letter already drawn, to show palely either side of the one being
    /// drawn. "n" is the letter type designers space everything against (two
    /// straight sides); failing that an "o", failing that any small letter.
    private var neighbour: Glyph? {
        for key in ["n", "o"] + Self.characters.prefix(26) {
            if let glyph = hands.hand.glyphs[key]?.first(where: { !$0.isRare }) { return glyph }
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
                }
                .frame(minHeight: 24)

                if trying {
                    trial
                } else {
                    drawing
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .onAppear {
            // Start at the first character that has not been drawn yet.
            if let first = Self.characters.firstIndex(where: { (hands.hand.glyphs[$0] ?? []).isEmpty }) {
                index = first
            }
        }
    }

    // MARK: - Drawing a letter

    private var drawing: some View {
        VStack(alignment: .leading, spacing: 0) {
            strip
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(isScribble ? "a scribble" : label(character))
                    .font(style.font(isFreeform ? TypeSize.body : TypeSize.question))
                    .foregroundStyle(style.ink)
                Small(drawnNote)
                Spacer()
                // Always there, dimmed until there is something to forget, so the
                // square below never moves between one drawing and the next.
                Word("forget", tone: .grey, disabled: timesDrawn == 0, size: TypeSize.small) { hands.forget(character) }
                    .accessibilityLabel("Forget every drawing of this character")
            }

            previous

            ruledSquare
                .padding(.top, 8)

            HStack(spacing: 24) {
                Word("keep", disabled: blank) { keep(advance: true) }
                    .accessibilityLabel("Keep this drawing and go to the next character")
                Word("again", disabled: blank) { keep(advance: false) }
                    .accessibilityLabel("Keep this drawing and draw the same character once more")
                // A drawing for now and then: a heart for the dot of an "i". A scribble
                // is already occasional, so it has no rare kind.
                if !isFreeform {
                    Word("rarely", disabled: blank) { keep(advance: false, rare: true) }
                        .accessibilityLabel("Keep this drawing as a rare one, used only now and then")
                }
                Word("clear", tone: .grey, disabled: blank) { strokes = []; inks = []; current = [] }
                Spacer()
            }
            .padding(.top, 8)
            // The pen's colour, chosen stroke by stroke: draw the stem of an "i" in
            // ink, switch to colour, and draw the heart. ColorPicker is the
            // system's colour chooser; the round swatch opens it.
            HStack(spacing: 24) {
                Small("pen")
                Word("ink", tone: inColour ? .faint : .ink, marked: !inColour) { inColour = false }
                    .accessibilityLabel("Draw the next strokes in ink")
                Word("colour", tone: inColour ? .ink : .faint, marked: inColour) { inColour = true }
                    .accessibilityLabel("Draw the next strokes in colour")
                ColorPicker("Pen colour", selection: $colour, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: colour) { inColour = true }
                Spacer()
            }
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

            // The app's icon is a picture file, not something drawn while the app
            // runs, so the drawing in the square is turned into that picture here.
            // Always there on the scribble entry, and only dimmed while the square
            // is empty: a row that appeared with the first stroke moved the page
            // under the pen and spoiled the drawing.
            if isScribble {
                HStack(spacing: 24) {
                    Word("make an icon of this", tone: .grey, disabled: blank) { iconURL = makeIcon() }
                    if let iconURL {
                        ShareLink(item: iconURL) {
                            Text("send the icon")
                                .font(style.font(TypeSize.word))
                                .foregroundStyle(style.ink)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PressedStyle())
                    }
                }
            }

            Small(drawingName != nil
                ? "A picture, not writing: draw it any size, anywhere in the square. Change the pen to colour for part of it. Draw it more than once with again and the app can vary them."
                : isScribble
                ? "A heart, a star, anything. Now and then one follows a line. Draw a few with again; the size you draw it is the size it gets."
                : "Draw it the way you write it, sitting on the line. Keep a drawing with rarely and it only turns up now and then, like a heart for a dot.")
                .padding(.top, 8)

            // Letters written as one shape. Name them here, then draw them like any other.
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Small("letters you join")
                Line(placeholder: "th", text: $joining, size: TypeSize.word, capitalization: .never, autocorrect: false, onSubmit: join)
                    .frame(width: 72)
                    .accessibilityLabel("Letters you write joined")
                Word("draw", tone: .grey, disabled: joining.trimmingCharacters(in: .whitespaces).count < 2, action: join)
                    .accessibilityLabel("Draw these joined letters")
            }
            // A picture the app shows by name. Name it here, then draw it like any other.
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
                                if glyph.isRare {
                                    Text("rare")
                                        .font(style.font(9))
                                        .foregroundStyle(style.grey)
                                        .padding(2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedStyle())
                    .accessibilityLabel("Drawing \(number + 1) of \(label(character))\(glyph.isRare ? ", rare" : "")")
                    .accessibilityAddTraits(picked == number ? .isSelected : [])
                }
                if let chosen = picked, kept.indices.contains(chosen) {
                    Word("forget this one", tone: .grey, size: TypeSize.small) {
                        hands.remove(at: chosen, for: character)
                        picked = nil
                    }
                }
            }
        }
        .frame(height: Self.thumb)
        .padding(.top, 4)
        // Another character has other drawings: nothing of this one is picked there.
        .onChange(of: character) { picked = nil }
    }

    private func thumbWidth(_ glyph: Glyph) -> CGFloat {
        isFreeform ? Self.thumb : max(40, CGFloat(glyph.advance) * Ruling.unit * Self.thumb + 16)
    }

    /// One kept drawing, small. A letter is shown sitting on its line, at the
    /// size it has against the ruling, so a comma looks like a comma and not
    /// like a letter-sized blob. A picture or a scribble fills the box.
    @ViewBuilder
    private func thumbnail(_ glyph: Glyph) -> some View {
        if isFreeform {
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
                        style: StrokeStyle(lineWidth: max(1, Pen.nib * unit), lineCap: .round, lineJoin: .round)
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
                        ForEach(all.filter { $0 != Hand.scribble }, id: \.self) { entry in
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
        iconURL = nil
        strokes = []
        inks = []
        current = []
        index = all.firstIndex(of: entry) ?? index
    }

    /// The square you draw in: the ruled lines, what has been drawn, and the gesture that draws.
    private var ruledSquare: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            Canvas { graphics, size in
                let s = size.width
                let rules: [(y: CGFloat, color: Color, dash: [CGFloat])] = [
                    (Ruling.tall, style.rule, []),
                    (Ruling.middle, style.faint, [4, 6]),
                    (Ruling.baseline, style.grey, []),
                    (Ruling.tail, style.rule, []),
                ]
                for rule in rules {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: rule.y * s))
                    path.addLine(to: CGPoint(x: s, y: rule.y * s))
                    graphics.stroke(path, with: .color(rule.color), style: StrokeStyle(lineWidth: 1, dash: rule.dash))
                }

                // The pen is as thick here, against the ruling, as it will be on the page.
                let nib = Pen.nib * Ruling.unit * s

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
                            for stroke in neighbour.points where !stroke.isEmpty {
                                let placed = stroke.map {
                                    CGPoint(x: (origin + $0.x * Ruling.unit) * s, y: (Ruling.baseline + $0.y * Ruling.unit) * s)
                                }
                                graphics.stroke(
                                    Written.smooth(placed),
                                    with: .color(style.edge),
                                    style: StrokeStyle(lineWidth: nib, lineCap: .round, lineJoin: .round)
                                )
                            }
                        }
                    }
                }
                for (number, stroke) in (strokes + [current]).enumerated() where !stroke.isEmpty {
                    let scaled = stroke.map { CGPoint(x: $0.x * s, y: $0.y * s) }
                    // Finished strokes keep the colour they were drawn in; the one
                    // under the finger shows the pen as it is now.
                    let shade: Color = number < strokes.count ? strokeColor(number) : (inColour ? colour : style.ink)
                    graphics.stroke(
                        Written.smooth(scaled),
                        with: .color(shade),
                        style: StrokeStyle(lineWidth: nib, lineCap: .round, lineJoin: .round)
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
                        }
                        current = []
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: sizeClass == .regular ? 520 : 300)
        .overlay(Rectangle().stroke(style.edge, lineWidth: 1))
        .accessibilityLabel("Drawing square for \(label(character))")
    }

    /// The colour a finished stroke in the square was drawn in.
    private func strokeColor(_ number: Int) -> Color {
        inks.indices.contains(number) && inks[number] >= 0 ? Color(hex: UInt32(inks[number])) : style.ink
    }

    /// Saves what is in the square as one drawing of the current character.
    private func keep(advance: Bool, rare: Bool = false) {
        let points = strokes.flatMap { $0 }
        guard let left = points.map(\.x).min(), let right = points.map(\.x).max() else { return }
        func rounded(_ value: CGFloat) -> Double { (Double(value) * 1000).rounded() / 1000 }
        let flat = strokes.map { stroke in
            stroke.flatMap { [rounded(($0.x - left) / Ruling.unit), rounded(($0.y - Ruling.baseline) / Ruling.unit)] }
        }
        let glyph = Glyph(
            strokes: flat,
            advance: max(0.12, rounded((right - left) / Ruling.unit)),
            rare: rare ? true : nil,
            colors: inks.contains { $0 >= 0 } ? inks : nil
        )
        hands.add(glyph, for: character)
        Haptic.success()
        strokes = []
        inks = []
        current = []
        if advance { move(1) }
    }

    /// Turns the drawing in the square into the app icon: a 1024 by 1024 PNG,
    /// white paper, the drawing in ink, centred, with the thick line an icon
    /// needs to read when it is small. Saved as icon.png, so it can replace
    /// the file of that name in the app's AppIcon.appiconset as it is.
    private func makeIcon() -> URL? {
        let points = strokes.flatMap { $0 }
        guard let left = points.map(\.x).min(), let right = points.map(\.x).max(),
              let top = points.map(\.y).min(), let bottom = points.map(\.y).max() else { return nil }
        let side: CGFloat = 1024
        // The drawing fills a little over half the icon, whatever size it was drawn.
        let scale = side * 0.56 / max(right - left, bottom - top, 0.01)
        let midX = (left + right) / 2
        let midY = (top + bottom) / 2

        // An icon may not be see-through, and must be exactly this many pixels.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor(style.paper).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let pen = context.cgContext
            pen.setLineWidth(side * 0.05)
            pen.setLineCap(.round)
            pen.setLineJoin(.round)
            // One stroke at a time, each in the colour it was drawn in.
            for (number, stroke) in strokes.enumerated() {
                let placed = stroke.map { CGPoint(x: side / 2 + ($0.x - midX) * scale, y: side / 2 + ($0.y - midY) * scale) }
                pen.setStrokeColor(UIColor(strokeColor(number)).cgColor)
                pen.addPath(Written.smooth(placed).cgPath)
                pen.strokePath()
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("icon.png")
        guard let data = image.pngData(), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        Haptic.success()
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
        current = []
        index = all.firstIndex(of: key) ?? index
    }

    private func move(_ step: Int) {
        iconURL = nil
        strokes = []
        inks = []
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
            Spacer().frame(height: 24)
        }
    }
}

// MARK: - The page's own small views
//
// Private to this file, so they cannot clash with an app's views of the same
// name. They read the style from the environment, which HandEditor sets.

private struct HandStyleKey: EnvironmentKey {
    static let defaultValue = HandStyle.journal
}

private extension EnvironmentValues {
    var handStyle: HandStyle {
        get { self[HandStyleKey.self] }
        set { self[HandStyleKey.self] = newValue }
    }
}

private enum TypeSize {
    static let question: CGFloat = 30
    static let body: CGFloat = 19
    static let word: CGFloat = 15
    static let small: CGFloat = 13
}

private enum WordTone {
    case ink, grey, faint
}

/// A word you can tap. The page has no buttons: actions are words.
private struct Word: View {
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

/// Small grey text: a count, a hint.
private struct Small: View {
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
private struct PressedStyle: ButtonStyle {
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
