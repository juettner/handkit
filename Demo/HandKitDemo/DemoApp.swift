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

    private let style = HandStyle.journal

    /// Pictures kept in the hand beside the letters. P.S. shows these two as its envelopes.
    static let pictures = ["envelope-sealed", "envelope-open"]

    var body: some View {
        ZStack {
            style.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                // The whole library in one `if`: is there a hand, and can it write this?
                if let hand = hands.active {
                    Handwriting(text: text, hand: hand, size: 34, ink: style.ink, seed: again)
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
            }
            .padding(32)
        }
        // A page that slides up over this one. HandEditor's "back" closes it.
        .fullScreenCover(isPresented: $drawing) {
            // The pictures the apps using this hand need, so they are on the page
            // ready to draw. Add a name here when an app needs another.
            HandEditor(style: style, drawings: DemoView.pictures)
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
