//
//  Handwriting.swift
//
//  A line written onto the page with a pen, in a hand.
//
//      Handwriting(text: "good morning", hand: hand)
//
//  A typewriter puts a whole letter down at once. A pen does not: the line
//  grows from the nib, stroke by stroke, and that is what "flow" means here.
//
//  Two pieces live in this file (the arithmetic is in Written.swift):
//
//    WritingLayout  tells SwiftUI how tall the line is at a given width. A
//                   Text does this by itself; drawn strokes do not, so the
//                   same arithmetic is asked for the height.
//    Handwriting    the view. A Canvas (an immediate-mode drawing surface,
//                   like a Java Graphics2D in paintComponent) redrawn by a
//                   TimelineView on every frame while the pen is moving.
//                   Finished strokes are drawn whole; the stroke in progress
//                   is drawn up to where the nib has got to.
//
//  Fresh ink is wet: at full strength and a touch wider. It dries to the
//  letter's own shade over `dryTime`, so with a long drying time the line
//  visibly settles into the paper behind the nib.
//  Tapping finishes the line at once. Reduce Motion shows it finished. The
//  phone ticks as each word starts. VoiceOver reads the text as ordinary
//  text.
//
//  The view writes whatever it is given. A character the hand has no
//  drawing for is left out, so check `hand.covers(text)` first if a line
//  must be complete (and show it another way when it is not), or
//  `hand.missing(in:)` to say which characters those are.
//
//  It can also sign. Give it `signatures` (drawings made on SignaturePad) and
//  the pen puts one under the writing when the words are done. With an empty
//  text and an empty hand it writes the signature alone, which is how an app
//  signs a note it has set in type:
//
//      Handwriting(text: "", hand: Hand(), signatures: signatures)
//

import SwiftUI

/// Sizes the drawing: as wide as it is offered, as tall as the lines need.
private struct WritingLayout: Layout {
    let text: String
    let hand: Hand
    let xHeight: CGFloat
    let playful: Bool
    let seed: Int
    let looseness: Double
    let slant: Double
    let signatures: [Glyph]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal size (no width), it answers with one long line.
        guard let width = proposal.width, width.isFinite, width > 0 else {
            let size = Written(text, hand: hand, xHeight: xHeight, width: .greatestFiniteMagnitude, lettersPerSecond: 0, playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures).size
            // Rounded up to a whole point. The drawing is worked out again at whatever width this view is then
            // given, and SwiftUI snaps that width to the pixel grid. Given a hair less than the line needs, the
            // last word would no longer fit and would drop to a second line that nobody made room for.
            return CGSize(width: size.width.rounded(.up), height: size.height)
        }
        let written = Written(text, hand: hand, xHeight: xHeight, width: width, lettersPerSecond: 0, playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures)
        return CGSize(width: width, height: written.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Remembers the last line worked out, so a frame of animation does not redo it.
private final class WrittenCache {
    var key = ""
    var written: Written?
}

public struct Handwriting: View {
    let text: String
    let hand: Hand
    /// The type size a typed line of the same height would have, in points.
    var size: CGFloat = 30
    /// The colour of ordinary ink. Strokes drawn in a colour of their own keep it.
    var ink: Color = HandStyle.journal.ink
    /// Letters per second, on average. Zero or less writes nothing: the line is just there.
    var speed: Double = Pen.lettersPerSecond
    /// Tick as each word starts.
    var haptics = true
    /// Allows the rare drawings and the scribbles. Off for lines that should stay plain.
    var playful = true
    /// Picks the drawings differently for the same text. Zero is the usual way.
    var seed = 0
    /// How unevenly the letters are put down. 1 is the usual hand; more is looser.
    var looseness: Double = 1
    /// How far the letters lean forward. 0 is as drawn; 0.15 is a hurry.
    var slant: Double = 0
    /// How long the ink stays wet, in seconds.
    var dryTime: TimeInterval = Pen.dryTime
    /// One person's signature, drawn one or more times (see SignaturePad). The
    /// pen signs under the writing with one of them. Empty for no signature.
    var signatures: [Glyph] = []
    /// Called once the whole line is on the page (written or tapped through).
    var onDone: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Follows the text size chosen in Settings, as a font would.
    @ScaledMetric private var textScale: CGFloat = 1
    @State private var began = Date()
    /// True once nothing is moving or drying; pauses the redraw.
    @State private var still = false
    /// True once the line was tapped through.
    @State private var skipped = false
    @State private var cache = WrittenCache()

    public init(
        text: String,
        hand: Hand,
        size: CGFloat = 30,
        ink: Color = HandStyle.journal.ink,
        speed: Double = Pen.lettersPerSecond,
        haptics: Bool = true,
        playful: Bool = true,
        seed: Int = 0,
        looseness: Double = 1,
        slant: Double = 0,
        dryTime: TimeInterval = Pen.dryTime,
        signatures: [Glyph] = [],
        onDone: (() -> Void)? = nil
    ) {
        self.text = text
        self.hand = hand
        self.size = size
        self.ink = ink
        self.speed = speed
        self.haptics = haptics
        self.playful = playful
        self.seed = seed
        self.looseness = looseness
        self.slant = slant
        self.dryTime = dryTime
        self.signatures = signatures
        self.onDone = onDone
    }

    private var xHeight: CGFloat { size * Pen.xHeightPerSize * textScale }

    public var body: some View {
        WritingLayout(text: text, hand: hand, xHeight: xHeight, playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures) {
            TimelineView(.animation(paused: still)) { context in
                Canvas { graphics, canvasSize in
                    let elapsed: TimeInterval = still ? .infinity : context.date.timeIntervalSince(began)
                    draw(written(for: canvasSize.width), at: elapsed, in: &graphics)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finishNow() }
        .task(id: text) { await write() }
        // The strokes mean nothing to VoiceOver; the words do (without the marks that cross some of them out).
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    /// What VoiceOver says: the words (without the marks that cross some of them out), and that it is signed.
    private var spoken: String {
        let words = Hand.unstruck(text)
        if signatures.isEmpty { return words }
        return words.isEmpty ? "Signature" : "\(words). Signed."
    }

    private func written(for width: CGFloat) -> Written {
        let key = "\(text)|\(width)|\(xHeight)|\(speed)|\(playful)|\(seed)|\(looseness)|\(slant)|\(signatures.count)"
        if cache.key == key, let written = cache.written { return written }
        let written = Written(text, hand: hand, xHeight: xHeight, width: width, lettersPerSecond: speed, playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures)
        cache.key = key
        cache.written = written
        return written
    }

    private func draw(_ written: Written, at elapsed: TimeInterval, in graphics: inout GraphicsContext) {
        for mark in written.marks {
            let age = elapsed - mark.start
            if age <= 0 { continue }
            // How much of the stroke is down. It eases out, so the pen slows into the end of a stroke.
            let progress = mark.duration > 0 ? min(1, age / mark.duration) : 1
            let eased = 1 - pow(1 - progress, 1.6)
            // 1 while the stroke is being made, 0 once it has dried.
            let wet = dryTime > 0 ? min(1, max(0, 1 - (age - mark.duration) / dryTime)) : 0
            let path = eased < 1 ? mark.path.trimmedPath(from: 0, to: eased) : mark.path
            graphics.stroke(
                path,
                with: .color((mark.color ?? ink).opacity(mark.ink + (1 - mark.ink) * wet)),
                // Wet ink stands a little proud of the paper, and sinks in as it dries.
                style: StrokeStyle(lineWidth: mark.width * (1 + Pen.wetSpread * CGFloat(wet)), lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Writing

    private func write() async {
        skipped = false
        // Timing does not depend on where the lines break, so any width will do here.
        let plan = Written(text, hand: hand, xHeight: xHeight, width: .greatestFiniteMagnitude, lettersPerSecond: speed, playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures)
        if reduceMotion || speed <= 0 || plan.marks.isEmpty {
            still = true
            onDone?()
            return
        }

        if haptics { Haptic.prepare() }
        began = Date()
        still = false
        for start in plan.wordStarts {
            await sleep(until: start)
            if Task.isCancelled { return }
            if skipped { break }
            if haptics { Haptic.tick() }
        }
        if !skipped { await sleep(until: plan.duration) }
        if Task.isCancelled { return }
        onDone?()

        // Let the last strokes dry, then stop redrawing.
        if !skipped { await sleep(until: plan.duration + dryTime + 0.1) }
        if !Task.isCancelled { still = true }
    }

    /// Sleeps until that many seconds after the pen started, in short naps so a tap is noticed quickly.
    private func sleep(until moment: TimeInterval) async {
        while !Task.isCancelled && !skipped {
            let left = moment - Date().timeIntervalSince(began)
            if left <= 0 { return }
            try? await Task.sleep(for: .seconds(min(left, 0.1)))
        }
    }

    /// The whole line, dry, now.
    private func finishNow() {
        skipped = true
        still = true
    }
}
