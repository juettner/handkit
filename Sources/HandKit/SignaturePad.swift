//
//  SignaturePad.swift
//
//  "Your signature": where you sign.
//
//  The drawing page (HandEditor) is for a whole alphabet, a character at a
//  time. This page is for one thing: sign on the line, tap "keep". Sign a
//  few times and the pen has a few to pick between, so two notes are not
//  signed with exactly the same strokes, as a stamp would.
//
//  A signature is a `Glyph`, the same data as a letter: pen strokes measured
//  in x-heights from a baseline (see Hand.swift). So everything that shows a
//  drawing shows a signature:
//
//      Handwriting(text: note, hand: hand, signatures: signatures)   the pen signs under the note
//      Handwriting(text: "", hand: Hand(), signatures: signatures)   the signature alone
//      GlyphView(signatures[0])                                      a still picture of one
//
//  Where the signatures are kept is the app's business, not this page's. The
//  page is handed a `Binding` to the list (a reference to a variable that
//  lives somewhere else: the page reads it, and writing to it changes the
//  original) and adds to it or removes from it. An app that keeps signatures
//  on a server sends the list there when it changes; the demo app keeps them
//  in the hand, as a drawing named "signature":
//
//      @State private var signatures: [Glyph] = []
//      ...
//      .fullScreenCover(isPresented: $signing) { SignaturePad(signatures: $signatures) }
//
//  The size it is signed at matters. The line on the page stands for a line
//  of writing, and one x-height is a fifth of the page's height, so a
//  signature that fills the page comes out about three lines of a note tall.
//  Sign smaller and it is written smaller.
//
//  The three short lines beside "clear" choose the pen: fine, medium or bold.
//  Each stroke keeps the line it was signed with, and the pen signs with it.
//
//  Nothing is smoothed or corrected, as on the drawing page. If a signature
//  has more points than an app would want to send over a network, every
//  other point is dropped until it does not; at this density the eye cannot
//  tell.
//
//  iOS only: it needs a finger (or a Pencil).
//

#if os(iOS)
import SwiftUI

/// The page to sign on, in fractions of its height.
private enum Signing {
    /// Twice as wide as it is tall.
    static let aspect: CGFloat = 2
    /// The line the signature sits on.
    static let baseline: CGFloat = 0.7
    /// One x-height.
    static let unit: CGFloat = 0.2
    /// The most points and strokes one signature is kept with.
    static let points = 1200
    static let strokes = 60
}

@MainActor
public struct SignaturePad: View {
    @Environment(\.dismiss) private var dismiss
    /// Regular means there is room to spare: an iPad.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding private var signatures: [Glyph]
    private let limit: Int
    private let style: HandStyle
    private let onClose: (() -> Void)?

    /// Finished strokes of the signature being made, in fractions of the page's height.
    @State private var strokes: [[CGPoint]] = []
    /// How thick each finished stroke is, as a multiple of the usual line.
    @State private var weights: [Double] = []
    /// The line the pen is signing with.
    @State private var weight = LineWeight.medium
    /// The stroke under the finger.
    @State private var current: [CGPoint] = []
    /// Which of the signatures already kept is picked, in the row above the page.
    @State private var picked: Int? = nil

    /// How many signatures a person keeps unless the app says otherwise.
    public static let most = 5

    /// - Parameters:
    ///   - signatures: the list this page adds to and removes from.
    ///   - limit: the most that may be kept.
    ///   - style: the page's colours and typeface.
    ///   - onClose: what "back" does. Left out, it dismisses the page.
    public init(
        signatures: Binding<[Glyph]>,
        limit: Int = SignaturePad.most,
        style: HandStyle = .journal,
        onClose: (() -> Void)? = nil
    ) {
        _signatures = signatures
        self.limit = limit
        self.style = style
        self.onClose = onClose
    }

    private var blank: Bool { strokes.isEmpty && current.isEmpty }
    private var full: Bool { signatures.count >= limit }

    public var body: some View {
        ZStack {
            style.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Word("back", tone: .grey, size: TypeSize.small) {
                        if let onClose { onClose() } else { dismiss() }
                    }
                    Spacer()
                    Small(signatures.isEmpty ? "not signed yet" : "\(signatures.count) of \(limit) kept")
                }
                .frame(minHeight: 24)

                Text("your signature")
                    .font(style.font(TypeSize.question))
                    .foregroundStyle(style.ink)
                Small("Sign on the line, the way you would sign a card. Keep a few, and each note is signed a little differently.")
                    .padding(.top, 4)

                kept
                pickedLine

                page
                    .padding(.top, 8)

                HStack(spacing: 24) {
                    Word("keep", disabled: blank || full) { keep() }
                        .accessibilityLabel("Keep this signature")
                    Word("clear", tone: .grey, disabled: blank) { clear() }
                    Spacer()
                    LineChoice(weight: $weight)
                }
                .padding(.top, 8)

                // Below everything, so the page above never moves when it appears.
                if full {
                    Small("\(limit) is the most. Forget one to sign another.")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.handStyle, style)
    }

    // MARK: - The signatures already kept

    /// How tall the row of kept signatures is.
    private static let thumb: CGFloat = 56

    /// Every signature kept, small, in the order they were made. Tap one to
    /// pick it. The row keeps its height when it is empty, so the page below
    /// never moves under the pen.
    private var kept: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(signatures.enumerated()), id: \.offset) { number, glyph in
                    Button { picked = picked == number ? nil : number } label: {
                        GlyphView(glyph, ink: style.ink)
                            .padding(6)
                            .frame(width: Self.thumb * Signing.aspect, height: Self.thumb)
                            .overlay(Rectangle().stroke(picked == number ? style.ink : style.edge, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedStyle())
                    .accessibilityLabel("Signature \(number + 1) of \(signatures.count)")
                    .accessibilityAddTraits(picked == number ? .isSelected : [])
                }
            }
        }
        .frame(height: Self.thumb)
        .padding(.top, 12)
    }

    /// Forgetting the picked signature. Always there, dimmed until one is picked, so nothing below moves.
    private var pickedLine: some View {
        let chosen = picked.flatMap { signatures.indices.contains($0) ? $0 : nil }
        return HStack(spacing: 20) {
            Small(signatures.isEmpty ? "the ones you keep show here" : chosen == nil ? "tap one to forget it" : "this one")
            Spacer()
            Word("forget", tone: .grey, disabled: chosen == nil, size: TypeSize.small) {
                if let chosen { signatures.remove(at: chosen) }
                picked = nil
            }
            .accessibilityLabel("Forget this signature")
        }
    }

    // MARK: - Signing

    /// The page you sign on: the line, what has been drawn, and the gesture that draws.
    private var page: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            Canvas { graphics, size in
                let h = size.height
                let y = Signing.baseline * h

                // The line to sign on, and the small cross a form prints where it starts.
                var line = Path()
                line.move(to: CGPoint(x: 0.12 * h, y: y))
                line.addLine(to: CGPoint(x: size.width - 0.12 * h, y: y))
                graphics.stroke(line, with: .color(style.grey), lineWidth: 1)
                let centre = CGPoint(x: 0.17 * h, y: y - 0.1 * h)
                let arm = 0.035 * h
                var cross = Path()
                cross.move(to: CGPoint(x: centre.x - arm, y: centre.y - arm))
                cross.addLine(to: CGPoint(x: centre.x + arm, y: centre.y + arm))
                cross.move(to: CGPoint(x: centre.x + arm, y: centre.y - arm))
                cross.addLine(to: CGPoint(x: centre.x - arm, y: centre.y + arm))
                graphics.stroke(cross, with: .color(style.faint), lineWidth: 1)

                // The pen is as thick here, against the line, as it will be on a note.
                // That is the usual line; a stroke signed fine or bold is a multiple of it.
                let nib = Pen.nib * Signing.unit * h
                for (number, stroke) in (strokes + [current]).enumerated() where !stroke.isEmpty {
                    let scaled = stroke.map { CGPoint(x: $0.x * h, y: $0.y * h) }
                    // Finished strokes keep their line; the one under the finger shows the pen as it is now.
                    let thick = weights.indices.contains(number) ? CGFloat(weights[number]) : weight.rawValue
                    graphics.stroke(
                        Written.smooth(scaled),
                        with: .color(style.ink),
                        style: StrokeStyle(lineWidth: nib * thick, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .contentShape(Rectangle())
            // DragGesture reports the finger's position as it moves. With a
            // minimum distance of 0 it starts at the touch, so a dot is a stroke too.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Kept inside the page, in fractions of its height.
                        let point = CGPoint(
                            x: min(max(value.location.x / height, 0), Signing.aspect),
                            y: min(max(value.location.y / height, 0), 1)
                        )
                        // Skip points that have barely moved: they add noise, not shape.
                        if let last = current.last, hypot(point.x - last.x, point.y - last.y) * height < 2 { return }
                        current.append(point)
                    }
                    .onEnded { _ in
                        if !current.isEmpty && strokes.count < Signing.strokes {
                            strokes.append(current)
                            weights.append(Double(weight.rawValue))
                        }
                        current = []
                    }
            )
        }
        .aspectRatio(Signing.aspect, contentMode: .fit)
        .frame(maxWidth: sizeClass == .regular ? 520 : .infinity)
        .overlay(Rectangle().stroke(style.edge, lineWidth: 1))
        .accessibilityLabel("The page to sign on")
    }

    private func clear() {
        strokes = []
        weights = []
        current = []
    }

    /// Adds what is on the page to the list, as one more signature.
    private func keep() {
        guard !full else { return }
        let thin = Self.thinned(strokes, to: Signing.points)
        let points = thin.flatMap { $0 }
        guard let left = points.map(\.x).min(), let right = points.map(\.x).max() else { return }
        func rounded(_ value: CGFloat) -> Double { (Double(value) * 1000).rounded() / 1000 }
        // From fractions of the page into x-heights: x from the left edge of the ink, y from the line.
        let flat = thin.map { stroke in
            stroke.flatMap { [rounded(($0.x - left) / Signing.unit), rounded(($0.y - Signing.baseline) / Signing.unit)] }
        }
        signatures.append(Glyph(
            strokes: flat,
            advance: max(0.12, rounded((right - left) / Signing.unit)),
            widths: weights.contains { $0 != 1 } ? weights : nil
        ))
        Haptic.success()
        clear()
        picked = nil
    }

    /// Drops every other point of each stroke, keeping its two ends, until
    /// there are no more than `limit` points in all.
    private static func thinned(_ strokes: [[CGPoint]], to limit: Int) -> [[CGPoint]] {
        var out = strokes
        var count = out.reduce(0) { $0 + $1.count }
        while count > limit {
            out = out.map { stroke in
                guard stroke.count > 2 else { return stroke }
                var kept = stride(from: 0, to: stroke.count - 1, by: 2).map { stroke[$0] }
                kept.append(stroke[stroke.count - 1])
                return kept
            }
            let now = out.reduce(0) { $0 + $1.count }
            // Nothing left to drop (very many very short strokes): keep what there is.
            if now == count { break }
            count = now
        }
        return out
    }
}
#endif
