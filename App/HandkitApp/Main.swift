//
//  Main.swift
//
//  Handkit, the app: draw your handwriting, write with it, send what it wrote.
//
//  The library next door (Sources/HandKit) is the pen and the drawing page.
//  This folder is the product around them: a welcome, three pages behind a
//  tab bar, and nothing that is only of use to somebody building an app
//  (that is behind "developer tools" on the last page).
//
//    Main.swift      this file: where the app starts, and which page is showing
//    Theme.swift     the colors, the type and the few shapes every page uses
//    Welcome.swift   the first thing a new person sees
//    WriteView.swift type a note, watch the pen write it, share the picture
//    HandView.swift  every character, drawn or not, and the way to the drawing page
//    KeepView.swift  back the hand up, bring one in, start over
//    Pictures.swift  the pictures P.S. wants drawn, asked for with developer tools on
//
//  For a Java person: `@main` marks the class with `public static void
//  main`. `WindowGroup` is the window; what is inside it is the first screen.
//  `@AppStorage` is a field kept in the app's preferences (UserDefaults), so
//  it is still set the next time the app opens.
//
//  The same code is the iPhone app and the iPad app. Each page asks how much
//  room it has (`horizontalSizeClass`: compact on a phone, regular on an iPad
//  that is not sharing its screen) and lays itself out in one column or two.
//

import HandKit
import SwiftUI

@main
struct Main: App {
    /// False until the welcome has been seen once.
    @AppStorage("welcomed") private var welcomed = false
    /// True when the welcome was left by "Draw my letters": the drawing page opens straight away.
    @State private var drawFirst = false

    var body: some Scene {
        WindowGroup {
            Group {
                if welcomed {
                    Root(drawFirst: drawFirst)
                } else {
                    Welcome(
                        draw: {
                            drawFirst = true
                            welcomed = true
                        },
                        look: { welcomed = true }
                    )
                }
            }
            // The pages are paper: white, whatever the phone is set to.
            .preferredColorScheme(.light)
            .tint(Theme.ink)
        }
    }
}

/// The three pages.
enum Place: Hashable {
    case write, hand, keep
}

/// A request to open the drawing page, at a character or wherever it likes.
/// `Identifiable` (it has an `id`) is what lets SwiftUI show a page "for" it.
struct DrawingRequest: Identifiable {
    let id = UUID()
    /// The character to open at, or nil for the first one not drawn yet.
    let start: String?
}

struct Root: View {
    let drawFirst: Bool

    @ObservedObject private var hands = HandStore.shared
    @State private var place = Place.write
    /// Not nil while the drawing page is up.
    @State private var drawing: DrawingRequest? = nil
    /// So the drawing page opens by itself only once after the welcome.
    @State private var opened = false
    /// "Developer tools", on the last page.
    @AppStorage("developer") private var developer = false

    var body: some View {
        // A tab bar on both devices. On an iPhone it is along the bottom; an
        // iPad puts it where its system version puts tab bars.
        TabView(selection: $place) {
            WriteView(draw: draw)
                .tabItem { Label("Write", systemImage: "pencil.line") }
                .tag(Place.write)
            HandView(draw: draw)
                .tabItem { Label("My hand", systemImage: "hand.draw") }
                .tag(Place.hand)
            KeepView()
                .tabItem { Label("Keep", systemImage: "square.and.arrow.up") }
                .tag(Place.keep)
        }
        // The drawing page takes the whole screen: nothing else should be in
        // reach of a hand that is drawing.
        .fullScreenCover(item: $drawing) { request in
            // With developer tools on, the page also asks for the pictures
            // P.S. shows from this hand, one after another (Pictures.swift).
            HandEditor(
                style: Theme.style,
                drawings: developer ? Pictures.names : [],
                labels: Pictures.labels,
                sizes: Pictures.sizes,
                hints: Pictures.hints,
                references: Pictures.references,
                icon: developer,
                tools: developer,
                start: request.start
            )
        }
        .task {
            // Straight from the welcome to the first letter.
            if drawFirst && !opened && !hands.hasLetters {
                opened = true
                place = .hand
                drawing = DrawingRequest(start: nil)
            }
        }
    }

    private func draw(_ start: String?) {
        drawing = DrawingRequest(start: start)
    }
}

extension HandStore {
    /// True once any character has been drawn. (A hand can hold a signature and no letters.)
    var hasLetters: Bool {
        HandEditor.characters.contains { !(hand.glyphs[$0] ?? []).isEmpty }
    }

    /// The signatures, kept in the hand as a drawing named "signature", so
    /// they are saved, backed up and brought in with it.
    var signatures: [Glyph] {
        hand.drawings(named: "signature")
    }

    func setSignatures(_ signatures: [Glyph]) {
        set(signatures, for: Hand.drawingKey("signature"))
    }
}
