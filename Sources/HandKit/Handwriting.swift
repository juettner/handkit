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
//  Three things an app can ask of the pen beyond writing:
//
//    mirrored   the line is written backwards, right to left, to be read in
//               a mirror.
//    weather    what the sky has done to the ink (Weathering): in the rain it
//               runs a little down the page, in the sun it dries pale.
//    words      the pen is held: it writes only as many words as this, and
//               waits, nib on the paper, until the number goes up. The app
//               counts something (steps, say) and passes the count. While
//               the pen is held a tap does not finish the line.
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

/// The clock of a pen that is being held (`words`). An ordinary clock would
/// run on while the pen waits, and the next word would then appear all at
/// once. This one only moves while the pen is allowed to: it is told the time
/// on every frame, and stops at `limit`.
///
/// A class, so the drawing code and the task that waits for the pen share
/// the one object (a struct would be copied into each).
private final class PenClock {
    /// Seconds the pen has spent writing.
    private(set) var time: TimeInterval = 0
    private var last: Date?
    /// How many words the pen may write, as last told by the view.
    var allowed = 0

    func tick(_ now: Date, limit: TimeInterval) -> TimeInterval {
        if let last { time += max(0, now.timeIntervalSince(last)) }
        last = now
        time = min(time, limit)
        return time
    }

    func reset() {
        time = 0
        last = nil
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
    /// Written backwards, to be read in a mirror.
    var mirrored = false
    /// What the weather has done to the ink.
    var weather: Weathering = .dry
    /// How many words the pen may write so far, or nil for a pen that is not held.
    var words: Int? = nil
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
    @State private var hold = PenClock()

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
        mirrored: Bool = false,
        weather: Weathering = .dry,
        words: Int? = nil,
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
        self.mirrored = mirrored
        self.weather = weather
        self.words = words
        self.onDone = onDone
    }

    private var xHeight: CGFloat { size * Pen.xHeightPerSize * textScale }

    public var body: some View {
        WritingLayout(text: text, hand: hand, xHeight: xHeight, playful: playful, seed: seed, looseness: looseness, slant: slant, signatures: signatures) {
            TimelineView(.animation(paused: still)) { context in
                Canvas { graphics, canvasSize in
                    let line = written(for: canvasSize.width)
                    let elapsed: TimeInterval
                    if still {
                        elapsed = .infinity
                    } else if let words {
                        // A held pen: its own clock, which stops at the end of the last word it is allowed.
                        hold.allowed = words
                        elapsed = hold.tick(context.date, limit: line.moment(afterWords: words))
                    } else {
                        elapsed = context.date.timeIntervalSince(began)
                    }
                    if mirrored {
                        // Flip the page left to right: move its right edge to the left, then draw with x running backwards.
                        graphics.translateBy(x: canvasSize.width, y: 0)
                        graphics.scaleBy(x: -1, y: 1)
                    }
                    draw(line, at: elapsed, in: &graphics)
                }
            }
        }
        .contentShape(Rectangle())
        // A held pen is not hurried by a tap: the app holding it decides when it may write.
        .onTapGesture { if words == nil { finishNow() } }
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
            // In the sun the ink goes down dark like any other and loses its strength as it dries.
            let strength = weather == .sun ? Pen.sunFade + (1 - Pen.sunFade) * wet : 1
            graphics.stroke(
                path,
                with: .color((mark.color ?? ink).opacity((mark.ink + (1 - mark.ink) * wet) * strength)),
                // Wet ink stands a little proud of the paper, and sinks in as it dries.
                style: StrokeStyle(lineWidth: mark.width * (1 + Pen.wetSpread * CGFloat(wet)), lineCap: .round, lineJoin: .round)
            )
        }
        if weather == .rain { drawRun(written, at: elapsed, in: &graphics) }
    }

    /// Rain: behind the pen, each stroke bleeds a little way down the page.
    /// The run is drawn as three soft copies of the stroke, each lower and
    /// fainter than the last, on a blurred layer over the writing.
    private func drawRun(_ written: Written, at elapsed: TimeInterval, in graphics: inout GraphicsContext) {
        graphics.drawLayer { layer in
            layer.addFilter(.blur(radius: xHeight * 0.07))
            for (index, mark) in written.marks.enumerated() {
                // The run starts when the stroke is finished, and takes `runTime` to get where it is going.
                let age = elapsed - mark.start - mark.duration
                if age <= 0 { continue }
                let soaked = min(1, age / Pen.runTime)
                // Not every stroke runs the same distance. The stroke's number is scrambled into
                // a share between 0 and 1, the same one every time, so the page does not shimmer.
                let luck = Double((index &* 2_654_435_761) % 97) / 97
                let run = xHeight * Pen.runLength * CGFloat(soaked * (0.25 + 0.75 * luck))
                for step in 1...3 {
                    let part = CGFloat(step) / 3
                    layer.stroke(
                        mark.path.offsetBy(dx: 0, dy: run * part),
                        with: .color((mark.color ?? ink).opacity(mark.ink * 0.2 * Double(1.25 - part))),
                        style: StrokeStyle(lineWidth: mark.width * 1.3, lineCap: .round, lineJoin: .round)
                    )
                }
            }
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
        if words != nil {
            await writeHeld(plan)
            return
        }
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

    /// Writing with a held pen. There is nothing to sleep until, because when
    /// the next word may start is not known. So this looks at the pen's clock
    /// ten times a second: it ticks as each word starts, says when the line is
    /// done, and stops the redrawing once the last ink is dry.
    private func writeHeld(_ plan: Written) async {
        hold.reset()
        still = false
        var ticked = 0
        var done = false
        while !Task.isCancelled {
            // A word has started if the pen is allowed it and the clock has reached it.
            while ticked < plan.wordStarts.count, ticked < hold.allowed, hold.time >= plan.wordStarts[ticked] {
                if haptics { Haptic.tick() }
                ticked += 1
            }
            if !done, hold.time >= plan.duration {
                done = true
                onDone?()
            }
            if hold.time >= plan.duration + dryTime + 0.1 { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
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
