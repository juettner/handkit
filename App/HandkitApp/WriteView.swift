//
//  WriteView.swift
//
//  "Write": type a note, watch the pen write it, send the picture.
//
//  Two things are on the page: the sheet the pen writes on, and the desk
//  (the words being typed, the pen's settings, and what can be done with the
//  note). On an iPhone the sheet is above and the desk below, with the pen's
//  settings on a card that slides up. On an iPad they are side by side and
//  the settings are always out.
//
//  The pen does not start over at every key press: it waits until the typing
//  has stopped for a moment (`shown` is the text it was last given).
//
//  "Share" makes a picture of the note (Handwriting.image, in the library)
//  as wide as the sheet on screen, so the lines break where you saw them
//  break, and hands it to the system's share sheet.
//

import HandKit
import SwiftUI

/// The inks the pen can be filled with.
enum Ink: String, CaseIterable {
    case black, blueBlack, blue, sepia, green, red

    var name: String {
        switch self {
        case .black: return "Black"
        case .blueBlack: return "Blue-black"
        case .blue: return "Blue"
        case .sepia: return "Sepia"
        case .green: return "Green"
        case .red: return "Red"
        }
    }

    var color: Color {
        switch self {
        case .black: return Theme.ink
        case .blueBlack: return Color(red: 28 / 255, green: 40 / 255, blue: 74 / 255)
        case .blue: return Color(red: 30 / 255, green: 72 / 255, blue: 158 / 255)
        case .sepia: return Color(red: 96 / 255, green: 62 / 255, blue: 38 / 255)
        case .green: return Color(red: 32 / 255, green: 92 / 255, blue: 66 / 255)
        case .red: return Theme.heart
        }
    }
}

struct WriteView: View {
    /// Opens the drawing page, at a character or wherever it likes.
    let draw: (String?) -> Void

    @ObservedObject private var hands = HandStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Kept between visits: the note being written and how the pen is set.
    @AppStorage("draft") private var text = "good morning"
    @AppStorage("pen.size") private var size = 30.0
    @AppStorage("pen.slant") private var slant = 0.0
    @AppStorage("pen.looseness") private var looseness = 1.0
    @AppStorage("pen.ink") private var inkName = Ink.black.rawValue
    @AppStorage("pen.signed") private var signed = false

    /// The text the pen was last given: `text`, once the typing has paused.
    @State private var shown = ""
    /// Changing this makes the pen write the same words again, a little differently.
    @State private var seed = 0
    /// How wide the sheet is on screen, so the picture breaks its lines in the same places.
    @State private var sheetWidth: CGFloat = 0
    @State private var settingPen = false
    @State private var sharing: SharedFile? = nil
    /// True while the keyboard is up for the note.
    @FocusState private var typing: Bool

    /// The widest the writing runs: about a note card.
    private static let leafWidth: CGFloat = 420

    private var ink: Ink { Ink(rawValue: inkName) ?? .black }
    private var signatures: [Glyph] { signed ? hands.signatures : [] }
    private var hasWords: Bool { !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The characters of the note that have not been drawn, each once, in the order they come up.
    private var missing: [String] {
        var seen = Set<Character>()
        return hands.hand.missing(in: shown).filter { seen.insert($0).inserted }.map { String($0) }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            title
                            composer(lines: 3...12)
                            actions
                            Rule()
                            PenSettings(size: $size, slant: $slant, looseness: $looseness, inkName: $inkName, signed: $signed, canSign: !hands.signatures.isEmpty)
                        }
                        .padding(Theme.margin)
                    }
                    .frame(width: 360)
                    Rectangle().fill(Theme.edge).frame(width: 1).ignoresSafeArea()
                    leaf
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    title
                        .padding(.horizontal, Theme.margin)
                        .padding(.top, 28)
                    leaf
                    Rule()
                    VStack(alignment: .leading, spacing: 4) {
                        composer(lines: 1...4)
                        actions
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { if shown.isEmpty { shown = text } }
        // Runs again each time `text` changes, and the run before it is
        // cancelled: so the pen gets the words only once the typing has paused.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { shown = text }
        }
        .sheet(isPresented: $settingPen) {
            ScrollView {
                PenSettings(size: $size, slant: $slant, looseness: $looseness, inkName: $inkName, signed: $signed, canSign: !hands.signatures.isEmpty)
                    .padding(Theme.margin)
            }
            .background(Theme.paper.ignoresSafeArea())
            // A card over the lower half, so the writing above it can be seen changing.
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
        }
        .sheet(item: $sharing) { file in
            ShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
    }

    private var title: some View {
        Text("Write")
            .font(Theme.serif(.largeTitle, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - The sheet

    /// What the pen writes on, or what to do when it has nothing to write with.
    private var leaf: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !hands.hasLetters {
                    Text("Nothing to write with yet.")
                        .font(Theme.serif(.title2))
                        .foregroundStyle(Theme.ink)
                    Note("Draw your letters first. The small ones are enough to start: capitals borrow them until you draw your own.")
                    Button("Draw my letters") { draw(nil) }
                        .buttonStyle(PrimaryButton())
                        .padding(.top, 4)
                } else if !hasWords {
                    Note("Type something and the pen writes it here.")
                } else {
                    Handwriting(
                        text: shown, hand: hands.hand, size: CGFloat(size), ink: ink.color,
                        seed: seed, looseness: looseness, slant: slant, signatures: signatures
                    )
                    // A new id makes SwiftUI treat it as a new view, so the pen starts over.
                    .id("\(shown)#\(seed)")
                    if !missing.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Note("Not drawn yet, so left out: \(missing.joined(separator: "  "))")
                            Button("Draw \(missing.count == 1 ? "it" : "them")") { draw(missing.first) }
                                .buttonStyle(WordButton())
                        }
                    }
                }
            }
            .frame(maxWidth: Self.leafWidth, alignment: .leading)
            // Measures the sheet: a see-through layer behind it reports its width.
            .background(
                GeometryReader { room in
                    Color.clear
                        .onAppear { sheetWidth = room.size.width }
                        .onChange(of: room.size.width) { _, width in sheetWidth = width }
                }
            )
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: sizeClass == .regular ? .center : .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The desk

    /// The line the note is typed on. It grows to `lines` and then scrolls.
    private func composer(lines: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Something to write", text: $text, axis: .vertical)
                .lineLimit(lines)
                .font(Theme.serif(.body))
                .foregroundStyle(Theme.ink)
                .focused($typing)
                .padding(.vertical, 8)
                .accessibilityLabel("The note")
            Rectangle()
                .fill(typing ? Theme.ink : Theme.edge)
                .frame(height: 1)
        }
    }

    private var actions: some View {
        HStack(spacing: 22) {
            Button("Again") { seed += 1 }
                .buttonStyle(WordButton())
                .disabled(!hasWords || !hands.hasLetters)
                .accessibilityLabel("Write it again, a little differently")
            // On an iPad the pen's settings are already on the page.
            if sizeClass != .regular {
                Button("Pen") {
                    typing = false
                    settingPen = true
                }
                .buttonStyle(WordButton())
                .accessibilityLabel("The pen's size, ink and slant")
            }
            if typing {
                Button("Done") { typing = false }
                    .buttonStyle(WordButton(color: Theme.muted))
                    .accessibilityLabel("Put the keyboard away")
            }
            Spacer()
            Button("Share") { share() }
                .buttonStyle(SecondaryButton())
                .disabled(!hasWords || !hands.hasLetters)
                .opacity(!hasWords || !hands.hasLetters ? 0.45 : 1)
                .accessibilityLabel("Share the note as a picture")
        }
    }

    /// Makes the picture and opens the share sheet for it.
    private func share() {
        // Whatever was typed last, even if the pen had not caught up with it.
        shown = text
        typing = false
        guard let picture = Handwriting.image(
            text: text, hand: hands.hand, size: CGFloat(size), width: sheetWidth > 0 ? sheetWidth : 320,
            ink: ink.color, paper: Theme.paper, margin: 36,
            seed: seed, looseness: looseness, slant: slant, signatures: signatures
        ), let data = picture.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("note.png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        sharing = SharedFile(url: url)
    }
}

/// How the pen is set: its size, how far it leans, how evenly it writes, its
/// ink, and whether it signs. Each `@Binding` is a setting the page owns and
/// this view changes.
struct PenSettings: View {
    @Binding var size: Double
    @Binding var slant: Double
    @Binding var looseness: Double
    @Binding var inkName: String
    @Binding var signed: Bool
    /// Whether there is a signature to sign with.
    let canSign: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Part("Ink") {
                HStack(spacing: 14) {
                    ForEach(Ink.allCases, id: \.self) { ink in
                        Button { inkName = ink.rawValue } label: {
                            Circle()
                                .fill(ink.color)
                                .frame(width: 28, height: 28)
                                // A ring around the one the pen is filled with.
                                .padding(4)
                                .overlay(Circle().stroke(inkName == ink.rawValue ? Theme.ink : Color.clear, lineWidth: 1.5))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ink.name) ink")
                        .accessibilityAddTraits(inkName == ink.rawValue ? .isSelected : [])
                    }
                }
            }
            dial("Size", low: "small", high: "large", value: $size, range: 18...56)
            dial("Lean", low: "upright", high: "in a hurry", value: $slant, range: 0...0.3)
            dial("Hand", low: "careful", high: "loose", value: $looseness, range: 0...2.2)
            if canSign {
                Toggle(isOn: $signed) {
                    Text("Sign it")
                        .font(Theme.serif(.body))
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.ink)
            } else {
                Note("Add a signature on the My hand page and the pen can sign your notes.")
            }
        }
    }

    /// One setting: its name, a slider, and what each end of the slider means.
    private func dial(_ name: String, low: String, high: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        Part(name) {
            Slider(value: value, in: range)
                .tint(Theme.ink)
                .accessibilityLabel(name)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(Theme.serif(.caption))
            .foregroundStyle(Theme.grey)
            .accessibilityHidden(true)
        }
    }
}
