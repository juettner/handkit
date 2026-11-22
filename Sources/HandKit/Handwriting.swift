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
//  Fresh ink is at full strength and dries to the letter's own shade.
//  Tapping finishes the line at once. Reduce Motion shows it finished. The
//  phone ticks as each word starts. VoiceOver reads the text as ordinary
//  text.
//
//  The view writes whatever it is given. A character the hand has no
//  drawing for is left out, so check `hand.covers(text)` first if a line
//  must be complete (and show it another way when it is not), or
//  `hand.missing(in:)` to say which characters those are.
//

import SwiftUI

/// Sizes the drawing: as wide as it is offered, as tall as the lines need.
private struct WritingLayout: Layout {
    let text: String
    let hand: Hand
    let xHeight: CGFloat
    let playful: Bool
    let seed: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal size (no width), it answers with one long line.
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return Written(text, hand: hand, xHeight: xHeight, width: .greatestFiniteMagnitude, lettersPerSecond: 0, playful: playful, seed: seed).size
        }
        let written = Written(text, hand: hand, xHeight: xHeight, width: width, lettersPerSecond: 0, playful: playful, seed: seed)
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
        self.onDone = onDone
    }

    private var xHeight: CGFloat { size * Pen.xHeightPerSize * textScale }

    public var body: some View {
        WritingLayout(text: text, hand: hand, xHeight: xHeight, playful: playful, seed: seed) {
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
        // The strokes mean nothing to VoiceOver; the words do.
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    private func written(for width: CGFloat) -> Written {
        let key = "\(text)|\(width)|\(xHeight)|\(speed)|\(playful)|\(seed)"
        if cache.key == key, let written = cache.written { return written }
        let written = Written(text, hand: hand, xHeight: xHeight, width: width, lettersPerSecond: speed, playful: playful, seed: seed)
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
            let wet = max(0, 1 - (age - mark.duration) / Pen.dryTime)
            let path = eased < 1 ? mark.path.trimmedPath(from: 0, to: eased) : mark.path
            graphics.stroke(
                path,
                with: .color((mark.color ?? ink).opacity(mark.ink + (1 - mark.ink) * min(1, wet))),
                style: StrokeStyle(lineWidth: mark.width, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Writing

    private func write() async {
        skipped = false
        // Timing does not depend on where the lines break, so any width will do here.
        let plan = Written(text, hand: hand, xHeight: xHeight, width: .greatestFiniteMagnitude, lettersPerSecond: speed, playful: playful, seed: seed)
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
        if !skipped { await sleep(until: plan.duration + Pen.dryTime + 0.1) }
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
