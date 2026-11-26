//
//  Theme.swift
//
//  What every page shares: the paper and ink (the library's own `journal`
//  style, so the drawing page and the pages around it are one place), the
//  type, and a handful of small views.
//
//  The type is the system serif at the system's text styles (`.title`,
//  `.body` and so on) and not at fixed sizes, so it grows with the text size
//  chosen in Settings.
//

import HandKit
import SwiftUI
import UIKit

enum Theme {
    static let style = HandStyle.journal
    static let paper = style.paper
    static let ink = style.ink
    static let grey = style.grey
    static let muted = style.muted
    static let faint = style.faint
    static let rule = style.rule
    static let edge = style.edge
    static let heart = style.heart

    /// The page's margin, and the widest a column of reading gets.
    static let margin: CGFloat = 28
    static let column: CGFloat = 680

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

/// A page that scrolls: a large title, then whatever the page holds, in a
/// column that stays readable on an iPad.
struct Page<Content: View>: View {
    let title: String
    let content: Content

    /// `@ViewBuilder` lets the caller write the page's views in braces, the way `VStack` does.
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: Theme.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// A part of a page: a small heading in capitals, then its views.
struct Part<Content: View>: View {
    let heading: String
    let content: Content

    init(_ heading: String, @ViewBuilder content: () -> Content) {
        self.heading = heading
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading.uppercased())
                .font(Theme.serif(.caption, weight: .medium))
                .kerning(1.2)
                .foregroundStyle(Theme.grey)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Quiet text: an explanation, a count.
struct Note: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.serif(.subheadline))
            .foregroundStyle(Theme.muted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The one thing a page most wants done: ink, with the words in paper.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(.body, weight: .medium))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 26)
            .frame(minHeight: 50)
            .background(Theme.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Something else that can be done: an outline.
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(.callout, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().stroke(Theme.edge, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}

/// A word that can be tapped, as on the drawing page.
struct WordButton: ButtonStyle {
    var color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(.callout))
            .foregroundStyle(color)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A hairline between two parts of a page.
struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.edge)
            .frame(height: 1)
    }
}

/// The system's share sheet (AirDrop, Messages, Save Image) for a file.
/// SwiftUI's own `ShareLink` needs the thing to share before it is tapped;
/// this is shown after the picture has been made. `UIViewControllerRepresentable`
/// is how a UIKit screen is put inside a SwiftUI one.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file about to be shared.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
