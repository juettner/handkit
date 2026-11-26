//
//  HandView.swift
//
//  "My hand": everything that can be drawn, and how much of it has been.
//
//  At the top, how far along the hand is and what to do next. Under that,
//  every character in a box: your drawing of it if there is one, the typed
//  character in pale grey if not. Tapping a box opens the drawing page at
//  that character. Last, the signature.
//
//  The grid is `LazyVGrid` with an "adaptive" column: as many boxes to a row
//  as fit, so the same code gives six across on a phone and a dozen on an iPad.
//

import HandKit
import SwiftUI

struct HandView: View {
    /// Opens the drawing page, at a character or wherever it likes.
    let draw: (String?) -> Void

    @ObservedObject private var hands = HandStore.shared
    @State private var signing = false

    /// The characters, in the groups the page shows them in. Together they
    /// are HandEditor.characters, which is the list the drawing page walks.
    /// (The two backslashes are one: that is how Swift spells a backslash.)
    private static let groups: [(title: String, characters: [String])] = [
        ("Small letters", split("abcdefghijklmnopqrstuvwxyz")),
        ("Punctuation", split(".,?'!-\":;()&/")),
        ("Numbers", split("0123456789")),
        ("Capitals", split("ABCDEFGHIJKLMNOPQRSTUVWXYZ")),
        ("Other marks", split("@#$%*+=~_<>[]{}|\\^`")),
    ]
    private static let small = split("abcdefghijklmnopqrstuvwxyz")

    private static func split(_ characters: String) -> [String] {
        characters.map { String($0) }
    }

    private func count(_ character: String) -> Int { hands.hand.glyphs[character]?.count ?? 0 }
    private var drawn: Int { HandEditor.characters.filter { count($0) > 0 }.count }
    private var smallLeft: Int { Self.small.filter { count($0) == 0 }.count }
    /// Letters drawn as one shape ("th"): whatever the hand holds that is longer than a character and not a picture.
    private var joined: [String] {
        hands.hand.glyphs.keys.filter { $0.count > 1 && Hand.drawingName(of: $0) == nil }.sorted()
    }

    /// What to do next, in a sentence.
    private var advice: String {
        if drawn == 0 {
            return "Start with the small letters. They are enough to write most things, and they take a few minutes."
        }
        if smallLeft > 0 {
            return "\(smallLeft) small \(smallLeft == 1 ? "letter" : "letters") to go before the pen can write most sentences."
        }
        if drawn < HandEditor.characters.count {
            return "The pen can write most things now. A capital borrows the small letter until you draw it. Draw a letter two or three times and repeated letters stop looking stamped."
        }
        return "Everything is drawn. Draw your favorites again for variety: the pen takes turns between them."
    }

    var body: some View {
        Page("My hand") {
            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: Double(drawn), total: Double(HandEditor.characters.count))
                    .tint(Theme.ink)
                    .accessibilityLabel("\(drawn) of \(HandEditor.characters.count) characters drawn")
                Text("\(drawn) of \(HandEditor.characters.count) drawn")
                    .font(Theme.serif(.headline))
                    .foregroundStyle(Theme.ink)
                Note(advice)
                Button(drawn == 0 ? "Start drawing" : "Keep drawing") { draw(nil) }
                    .buttonStyle(PrimaryButton())
                    .padding(.top, 6)
            }

            ForEach(Self.groups, id: \.title) { group in
                Part(group.title) { grid(group.characters) }
            }
            Part("Extras") {
                grid([Hand.scribble] + joined)
                Note("The heart is a scribble: a heart, a star, anything. Now and then one follows a line. Letters you write as one shape, like \"th\", can be drawn as one on the drawing page.")
            }

            Rule()
            signature
        }
        .fullScreenCover(isPresented: $signing) {
            // `Binding(get:set:)` is a pair of functions the signing page calls
            // to read the list and to change it.
            SignaturePad(
                signatures: Binding(get: { hands.signatures }, set: { hands.setSignatures($0) }),
                style: Theme.style
            )
        }
    }

    // MARK: - The boxes

    private func grid(_ characters: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 50, maximum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(characters, id: \.self) { character in
                box(character)
            }
        }
    }

    /// One character: the first drawing of it, or the typed character, pale.
    private func box(_ character: String) -> some View {
        let times = count(character)
        let name = character == Hand.scribble ? "scribble" : character
        return Button { draw(character) } label: {
            ZStack {
                if let glyph = hands.hand.glyphs[character]?.first {
                    if character == Hand.scribble {
                        // A scribble is any size, anywhere: fitted to the box.
                        GlyphView(glyph, ink: Theme.ink)
                            .padding(10)
                    } else {
                        // A letter sits on its line, at its own size against it.
                        LetterView(glyph, ink: Theme.ink)
                    }
                } else {
                    Text(character)
                        .font(Theme.serif(.title3))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(times > 0 ? Theme.edge : Theme.rule, lineWidth: 1))
            // Handwriting is not always easy to read one letter at a time: say which this is.
            .overlay(alignment: .bottomLeading) {
                if times > 0 {
                    Text(character)
                        .font(.system(size: 9, design: .serif))
                        .foregroundStyle(Theme.grey)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                }
            }
            // How many drawings there are, once there is more than one.
            .overlay(alignment: .topTrailing) {
                if times > 1 {
                    Text("\(times)")
                        .font(.system(size: 9, design: .serif))
                        .foregroundStyle(Theme.grey)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(times == 0 ? "\(name), not drawn yet" : times == 1 ? "\(name), drawn once" : "\(name), drawn \(times) times")
        .accessibilityHint("Opens the drawing page")
    }

    // MARK: - The signature

    private var signature: some View {
        Part("Signature") {
            if let first = hands.signatures.first {
                GlyphView(first, ink: Theme.ink)
                    .frame(width: 180, height: 72)
                    .accessibilityLabel("Your signature")
                Note(hands.signatures.count == 1
                    ? "One kept. Keep a few and each note is signed a little differently."
                    : "\(hands.signatures.count) kept. The pen picks one for each note.")
                Button("Sign again, or forget one") { signing = true }
                    .buttonStyle(SecondaryButton())
            } else {
                Note("Sign once, the way you would sign a card, and the pen can sign your notes.")
                Button("Add my signature") { signing = true }
                    .buttonStyle(SecondaryButton())
            }
        }
    }
}
