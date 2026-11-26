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
    /// covers, and the last three in the strip at the top of its reader's page.
    static let pictures = ["envelope-sealed", "envelope-open", "drawer", "map", "flashlight", "doodle", "status-signal", "status-wifi", "status-battery"]
    /// What the drawing page calls the ones whose names would read oddly.
    static let labels = ["status-signal": "signal", "status-wifi": "wifi", "status-battery": "battery"]
    /// The pictures P.S. only ever shows small, at these sizes in points, so
    /// the drawing page gives each a box of that shape to fill and shows what
    /// is kept at its real size: the drawer and the map in its reader's row of
    /// envelopes (Pinned.swift there), the flashlight on a dark page
    /// (Reveals.swift), and the three in the strip at the top of its reader's
    /// page (HandStatusBar.swift).
    static let sizes = [
        "drawer": CGSize(width: 44, height: 44),
        "map": CGSize(width: 44, height: 44),
        "flashlight": CGSize(width: 40, height: 40),
        "status-signal": CGSize(width: 18, height: 12),
        "status-wifi": CGSize(width: 17, height: 12),
        "status-battery": CGSize(width: 27, height: 13),
    ]

    /// What the drawing page says about a picture while it is being drawn.
    static let hints = [
        "drawer": "The drawer: where the envelopes that cannot be opened yet are kept. P.S. pins it at the lower left of the reader's row of envelopes, with \"drawer\" written under it. Only the first one you keep is used.",
        "map": "The map: everywhere a note has found the reader. P.S. pins it beside the drawer, with \"map\" written under it. Only the first one you keep is used.",
        "flashlight": "The flashlight: P.S. shows it in the middle of the dark page of a note read under the covers, until the reader taps to turn on the light. Draw it in plain ink: the page is dark, so P.S. shows it in a pale ink. Only the first one you keep is used.",
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
            HandEditor(style: style, drawings: DemoView.pictures, labels: DemoView.labels, sizes: DemoView.sizes, hints: DemoView.hints)
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
