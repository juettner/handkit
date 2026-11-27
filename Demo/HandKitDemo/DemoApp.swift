//
//  DemoApp.swift
//
//  The smallest app that uses HandKit: one page that writes whatever you
//  type in your own handwriting, and a way to the page where you draw it.
//
//  Read this file top to bottom to see everything an app has to do:
//
//    1. `import HandKit`
//    2. get a hand                 HandStore.shared.active
//    3. write with it              Handwriting(text:hand:)
//    4. let somebody draw one      HandEditor()
//    5. let them sign              SignaturePad(signatures:), and
//                                  Handwriting(text:hand:signatures:)
//
//  For a Java person: `@main` marks the class with `public static void
//  main`. `WindowGroup` is the window; what is inside it is the first screen.
//

import HandKit
import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoView()
                .preferredColorScheme(.light)
        }
    }
}

struct DemoView: View {
    /// The store loads the hand (drawn on this phone, or shipped as hand.json)
    /// and saves what the editor draws. `@ObservedObject` means: redraw this
    /// view whenever the store's hand changes.
    @ObservedObject private var hands = HandStore.shared

    /// `@State` is a variable the view owns; changing it redraws the view.
    @State private var text = "good morning, love"
    /// Changing this number makes the pen write the line again, a little differently.
    @State private var again = 0
    @State private var drawing = false
    @State private var signing = false

    private let style = HandStyle.journal

    /// Pictures kept in the hand beside the letters, in the order the drawing
    /// page lists them. P.S. shows the first two as its envelopes, "drawer"
    /// and "map" pinned at the left of its reader's row of envelopes,
    /// "flashlight" in the middle of the dark page of a note read under the
    /// covers, "candle" and "candle-flame" the same way for a note read by
    /// candlelight, "seashell" on a note that came with the writer's voice,
    /// and the last three in the strip at the top of its reader's page.
    static let pictures = ["envelope-sealed", "envelope-open", "drawer", "map", "flashlight", "candle", "candle-flame", "seashell", "doodle", "status-signal", "status-wifi", "status-battery"]
    /// What the drawing page calls the ones whose names would read oddly.
    static let labels = ["candle-flame": "flame", "status-signal": "signal", "status-wifi": "wifi", "status-battery": "battery"]
    /// The pictures P.S. only ever shows small, at these sizes in points, so
    /// the drawing page gives each a box of that shape to fill and shows what
    /// is kept at its real size: the drawer and the map in its reader's row of
    /// envelopes (Pinned.swift there), the flashlight, the candle and its
    /// flame on a dark page (Reveals.swift), and the three in the strip at the top of its reader's
    /// page (HandStatusBar.swift).
    static let sizes = [
        "drawer": CGSize(width: 44, height: 44),
        "map": CGSize(width: 44, height: 44),
        "flashlight": CGSize(width: 44, height: 44),
        "candle": CGSize(width: 30, height: 44),
        "candle-flame": CGSize(width: 14, height: 22),
        "status-signal": CGSize(width: 18, height: 12),
        "status-wifi": CGSize(width: 17, height: 12),
        "status-battery": CGSize(width: 27, height: 13),
    ]

    /// What the drawing page says about a picture while it is being drawn.
    static let hints = [
        "drawer": "The drawer: where the envelopes that cannot be opened yet are kept. P.S. pins it at the lower left of the reader's row of envelopes, with \"drawer\" written under it. Only the first one you keep is used.",
        "map": "The map: everywhere a note has found the reader. P.S. pins it beside the drawer, with \"map\" written under it. Only the first one you keep is used.",
        "candle": "The candle, not burning: the wax and its wick, and no flame. For a note read by candlelight, the reader's whole screen is black with only this in the middle of it, until they tap to light it. Draw it in plain ink: P.S. shows it pale in the dark, and in ink once the page is lit. Only the first one you keep is used.",
        "candle-flame": "The flame, by itself. P.S. puts it on top of the candle when it is lit, with its foot on the wick, and lets it waver. Fill the box. In plain ink it is shown amber; give it a color of its own to keep that. Only the first one you keep is used.",
        "flashlight": "The flashlight: for a note read under the covers, the reader's whole screen is black with only this in the middle of it, until they tap to turn on the light. Draw it in plain ink: the page is dark, so P.S. shows it in a pale ink. Only the first one you keep is used.",
        "seashell": "A seashell, the kind you would hold to your ear to hear the sea. P.S. puts it on a note that came with the writer's voice, about as wide as three fingers, and the pen draws it stroke by stroke when the note is first opened: the reader holds the phone to their ear to hear it. Only the first one you keep is used.",
    ]

    /// One way to draw each picture, shown small and grey beside its hint: a
    /// few plain strokes to look at, not to trace. The numbers are x0, y0,
    /// x1, y1, ... as in a hand file; a corner is written twice so the pen's
    /// smoothing leaves it a corner. The doodle has none: it is whatever you like.
    static let references: [String: Glyph] = [
        "envelope-sealed": Glyph(strokes: [
            [0.0, 0.0, 3.36, 0.0, 3.36, 0.0, 3.36, 2.16, 3.36, 2.16, 0.0, 2.16, 0.0, 2.16, 0.0, 0.0],
            [0.0, 0.0, 1.68, 1.28, 1.68, 1.28, 3.36, 0.0],
        ], advance: 3.36),
        "envelope-open": Glyph(strokes: [
            [0.0, 1.36, 0.0, 3.28, 0.0, 3.28, 3.36, 3.28, 3.36, 3.28, 3.36, 1.36],
            [0.0, 1.36, 1.68, 0.0, 1.68, 0.0, 3.36, 1.36],
            [0.0, 1.36, 1.68, 2.4, 1.68, 2.4, 3.36, 1.36],
        ], advance: 3.36),
        "drawer": Glyph(strokes: [
            [0.0, 0.0, 3.04, 0.0, 3.04, 0.0, 3.04, 2.56, 3.04, 2.56, 0.0, 2.56, 0.0, 2.56, 0.0, 0.0],
            [0.0, 1.28, 3.04, 1.28],
            [1.68, 0.64, 1.65, 0.73, 1.57, 0.79, 1.47, 0.79, 1.39, 0.73, 1.36, 0.64, 1.39, 0.55, 1.47, 0.49, 1.57, 0.49, 1.65, 0.55, 1.68, 0.64],
            [1.68, 1.92, 1.65, 2.01, 1.57, 2.07, 1.47, 2.07, 1.39, 2.01, 1.36, 1.92, 1.39, 1.83, 1.47, 1.77, 1.57, 1.77, 1.65, 1.83, 1.68, 1.92],
            [0.24, 2.56, 0.24, 2.88],
            [2.8, 2.56, 2.8, 2.88],
        ], advance: 3.04),
        "map": Glyph(strokes: [
            [0.0, 0.48, 1.12, 0.0, 1.12, 0.0, 2.24, 0.48, 2.24, 0.48, 3.36, 0.0, 3.36, 0.0, 3.36, 2.4, 3.36, 2.4, 2.24, 2.88, 2.24, 2.88, 1.12, 2.4, 1.12, 2.4, 0.0, 2.88, 0.0, 2.88, 0.0, 0.48],
            [1.12, 0.0, 1.12, 2.4],
            [2.24, 0.48, 2.24, 2.88],
            [0.4, 2.16, 0.64, 1.92],
            [0.88, 1.68, 1.28, 1.6],
            [1.52, 1.68, 1.84, 1.84],
            [2.08, 1.84, 2.4, 1.6],
            [2.56, 1.04, 2.96, 1.44],
            [2.96, 1.04, 2.56, 1.44],
        ], advance: 3.36),
        "flashlight": Glyph(strokes: [
            [1.84, 0.48, 0.0, 0.48, 0.0, 0.48, 0.0, 1.28, 0.0, 1.28, 1.84, 1.28],
            [1.84, 0.48, 2.48, 0.0, 2.48, 0.0, 2.96, 0.0, 2.96, 0.0, 2.96, 1.76, 2.96, 1.76, 2.48, 1.76, 2.48, 1.76, 1.84, 1.28, 1.84, 1.28, 1.84, 0.48],
            [2.96, 0.0, 3.2, 0.0, 3.2, 0.0, 3.2, 1.76, 3.2, 1.76, 2.96, 1.76],
            [0.64, 0.24, 1.2, 0.24, 1.2, 0.24, 1.2, 0.48, 1.2, 0.48, 0.64, 0.48, 0.64, 0.48, 0.64, 0.24],
        ], advance: 3.2),
        "candle": Glyph(strokes: [
            [0.0, 0.64, 0.0, 3.12, 0.0, 3.12, 1.6, 3.12, 1.6, 3.12, 1.6, 0.64],
            [0.0, 0.64, 0.11, 0.54, 0.4, 0.47, 0.8, 0.44, 1.2, 0.47, 1.49, 0.54, 1.6, 0.64, 1.49, 0.74, 1.2, 0.81, 0.8, 0.84, 0.4, 0.81, 0.11, 0.74, 0.0, 0.64],
            [0.8, 0.64, 0.8, 0.32, 0.92, 0.0],
            [0.32, 0.84, 0.32, 1.36, 0.48, 1.52, 0.56, 1.28, 0.56, 0.84],
        ], advance: 1.6),
        "candle-flame": Glyph(strokes: [
            [1.12, 0.0, 1.13, 0.06, 1.18, 0.24, 1.28, 0.52, 1.42, 0.88, 1.6, 1.3, 1.75, 1.76, 1.86, 2.22, 1.87, 2.64, 1.77, 3.0, 1.57, 3.28, 1.27, 3.46, 0.92, 3.52, 0.58, 3.46, 0.28, 3.28, 0.08, 3.0, 0.0, 2.64, 0.04, 2.22, 0.19, 1.76, 0.41, 1.3, 0.65, 0.88, 0.86, 0.52, 1.02, 0.24, 1.1, 0.06, 1.12, 0.0],
        ], advance: 1.87),
        "seashell": Glyph(strokes: [
            [1.91, 2.7, 0.04, 1.98, 0.01, 1.85, 0.0, 1.73, 0.01, 1.61, 0.04, 1.49, 0.1, 1.39, 0.18, 1.3, 0.28, 1.22, 0.39, 1.15, 0.41, 1.03, 0.45, 0.91, 0.5, 0.8, 0.58, 0.71, 0.67, 0.63, 0.78, 0.58, 0.9, 0.54, 1.03, 0.52, 1.1, 0.42, 1.18, 0.32, 1.27, 0.24, 1.37, 0.18, 1.49, 0.15, 1.61, 0.14, 1.73, 0.16, 1.86, 0.18, 1.96, 0.11, 2.07, 0.05, 2.19, 0.01, 2.31, 0.0, 2.43, 0.01, 2.54, 0.05, 2.65, 0.11, 2.75, 0.18, 2.88, 0.16, 3.0, 0.14, 3.12, 0.15, 3.24, 0.18, 3.34, 0.24, 3.44, 0.32, 3.52, 0.42, 3.58, 0.52, 3.71, 0.54, 3.83, 0.58, 3.94, 0.63, 4.03, 0.71, 4.11, 0.8, 4.16, 0.91, 4.2, 1.03, 4.22, 1.15, 4.33, 1.22, 4.43, 1.3, 4.51, 1.39, 4.57, 1.49, 4.6, 1.61, 4.61, 1.73, 4.6, 1.85, 4.58, 1.98, 2.71, 2.7],
            [1.91, 2.7, 1.67, 2.7, 1.67, 2.7, 1.75, 3.1, 1.75, 3.1, 2.87, 3.1, 2.87, 3.1, 2.95, 2.7, 2.95, 2.7, 2.71, 2.7],
            [2.04, 2.4, 0.59, 1.29],
            [2.13, 2.34, 1.16, 0.72],
            [2.24, 2.3, 1.9, 0.42],
            [2.37, 2.3, 2.71, 0.42],
            [2.48, 2.34, 3.45, 0.72],
            [2.57, 2.4, 4.02, 1.29],
        ], advance: 4.61),
        "status-signal": Glyph(strokes: [
            [0.0, 1.6, 0.56, 1.6, 0.56, 1.6, 0.56, 2.24, 0.56, 2.24, 0.0, 2.24, 0.0, 2.24, 0.0, 1.6],
            [0.96, 1.12, 1.52, 1.12, 1.52, 1.12, 1.52, 2.24, 1.52, 2.24, 0.96, 2.24, 0.96, 2.24, 0.96, 1.12],
            [1.92, 0.56, 2.48, 0.56, 2.48, 0.56, 2.48, 2.24, 2.48, 2.24, 1.92, 2.24, 1.92, 2.24, 1.92, 0.56],
            [2.88, 0.0, 3.44, 0.0, 3.44, 0.0, 3.44, 2.24, 3.44, 2.24, 2.88, 2.24, 2.88, 2.24, 2.88, 0.0],
        ], advance: 3.44),
        "status-wifi": Glyph(strokes: [
            [0.0, 0.89, 0.39, 0.51, 0.85, 0.23, 1.36, 0.06, 1.9, 0.0, 2.44, 0.06, 2.95, 0.23, 3.41, 0.51, 3.8, 0.89],
            [0.68, 1.38, 0.98, 1.12, 1.32, 0.94, 1.7, 0.85, 2.1, 0.85, 2.48, 0.94, 2.82, 1.12, 3.12, 1.38],
            [1.33, 1.91, 1.54, 1.77, 1.77, 1.69, 2.02, 1.69, 2.26, 1.77, 2.47, 1.91],
            [2.06, 2.4, 2.03, 2.49, 1.95, 2.55, 1.85, 2.55, 1.77, 2.49, 1.74, 2.4, 1.77, 2.31, 1.85, 2.25, 1.95, 2.25, 2.03, 2.31, 2.06, 2.4],
        ], advance: 3.8),
        "status-battery": Glyph(strokes: [
            [0.0, 0.0, 3.2, 0.0, 3.2, 0.0, 3.2, 1.76, 3.2, 1.76, 0.0, 1.76, 0.0, 1.76, 0.0, 0.0],
            [3.52, 0.56, 3.52, 1.2],
            [0.32, 0.32, 2.24, 0.32, 2.24, 0.32, 2.24, 1.44, 2.24, 1.44, 0.32, 1.44, 0.32, 1.44, 0.32, 0.32],
        ], advance: 3.52),
    ]

    /// The signatures, kept in the hand as a drawing named "signature", so
    /// they are saved with it. `Binding(get:set:)` is a pair of functions the
    /// signing page calls to read the list and to change it. An app with
    /// accounts keeps each person's signatures on its server instead.
    private var signatures: Binding<[Glyph]> {
        Binding(
            get: { hands.hand.drawings(named: "signature") },
            set: { hands.set($0, for: Hand.drawingKey("signature")) }
        )
    }

    var body: some View {
        ZStack {
            style.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                // The whole library in one `if`: is there a hand, and can it write this?
                if let hand = hands.active {
                    Handwriting(text: text, hand: hand, size: 34, ink: style.ink, seed: again, signatures: signatures.wrappedValue)
                        // A new id makes SwiftUI treat it as a new view, so the pen starts over.
                        .id("\(text)#\(again)")

                    let missing = hand.missing(in: text)
                    if !missing.isEmpty {
                        note("Not drawn yet, so left out: \(missing.map(String.init).joined(separator: " "))")
                    }
                } else {
                    Text("No handwriting yet.")
                        .font(style.font(28))
                        .foregroundStyle(style.ink)
                    note("Tap \"draw my hand\" and draw a few letters. Start with the ones in the sentence below.")
                }

                Spacer()

                TextField("something to write", text: $text)
                    .font(style.font(19))
                    .foregroundStyle(style.ink)
                    .autocorrectionDisabled()
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(style.edge).frame(height: 1) }

                HStack(spacing: 28) {
                    word("write it again") { again += 1 }
                    word("draw my hand") { drawing = true }
                }
                word("my signature") { signing = true }
            }
            .padding(32)
        }
        // A page that slides up over this one. HandEditor's "back" closes it.
        .fullScreenCover(isPresented: $drawing) {
            // The pictures the apps using this hand need, so they are on the page
            // ready to draw. Add a name here when an app needs another.
            HandEditor(style: style, drawings: DemoView.pictures, labels: DemoView.labels, sizes: DemoView.sizes, hints: DemoView.hints, references: DemoView.references)
        }
        .fullScreenCover(isPresented: $signing) {
            SignaturePad(signatures: signatures, style: style)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(style.font(13))
            .foregroundStyle(style.grey)
    }

    private func word(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(style.font(16))
                .foregroundStyle(style.ink)
                .frame(minHeight: 44)
        }
    }
}
