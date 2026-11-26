//
//  Welcome.swift
//
//  The first thing a new person sees, once: what this is, in three short
//  lines, and the way in.
//
//  If the app ships a small hand named welcome.json (see App/README.md), the
//  line under the name is written by the pen, which shows what the app does
//  better than any sentence about it. Without the file the line is set in
//  type and nothing else changes.
//

import HandKit
import SwiftUI

struct Welcome: View {
    /// "Draw my letters": on to the app, with the drawing page open.
    let draw: () -> Void
    /// "Look around first".
    let look: () -> Void

    private static let line = "your handwriting, kept"
    /// The hand that writes the line, if one was shipped and has every letter of it.
    private static let sample: Hand? = {
        guard let url = Bundle.main.url(forResource: "welcome", withExtension: "json"),
              let hand = Hand(contentsOf: url), hand.covers(Welcome.line) else { return nil }
        return hand
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Handkit")
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)

                Group {
                    if let sample = Welcome.sample {
                        Handwriting(text: Welcome.line, hand: sample, size: 34, ink: Theme.ink, playful: false)
                    } else {
                        Text("Your handwriting, kept.")
                            .font(Theme.serif(.title2).italic())
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 10)

                VStack(alignment: .leading, spacing: 26) {
                    point("Draw your letters", "One at a time, with a finger or a Pencil. A few minutes gets you the alphabet.")
                    point("Write anything", "Type a note and a pen writes it in your hand, stroke by stroke, a little differently each time.")
                    point("It stays yours", "Your handwriting is kept on this device. There is no account and nothing is uploaded.")
                }
                .padding(.top, 44)

                VStack(alignment: .leading, spacing: 4) {
                    Button("Draw my letters", action: draw)
                        .buttonStyle(PrimaryButton())
                    Button("Look around first", action: look)
                        .buttonStyle(WordButton(color: Theme.muted))
                }
                .padding(.top, 44)
            }
            .padding(.horizontal, Theme.margin + 4)
            .padding(.top, 72)
            .padding(.bottom, 40)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.serif(.title3, weight: .medium))
                .foregroundStyle(Theme.ink)
            Note(text)
        }
    }
}
