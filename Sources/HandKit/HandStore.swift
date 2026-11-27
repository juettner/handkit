//
//  HandStore.swift
//
//  Where a hand lives on the phone.
//
//  Three places, looked in this order:
//
//    1. hand.json in the app's Application Support folder: letters drawn on
//       this device with HandEditor. If there are any, they win, so you see
//       your work as you draw.
//    2. hand.json shipped inside the app (in its bundle): the hand everybody
//       gets.
//    3. hand.json inside HandKit itself (the file beside this one): the hand
//       an app gets when it ships none, so the pen writes from the first run.
//       It is also `Hand.packaged`.
//
//  To ship a hand: draw it in HandEditor, tap "send my hand as a file", and
//  add the file to the app target as hand.json.
//
//  An app that is for drawing a hand wants to start with none, not with
//  somebody else's. It says so in its Info.plist:
//
//      <key>HandKitPackagedHand</key>
//      <false/>
//
//  Then only the first two places are looked in. If they are both empty the
//  hand is empty and `active` is nil: the app should show its text some
//  other way.
//
//  An app that does not let people draw never has a saved file, so it always
//  reads the shipped hand. An app that fetches hands from somewhere else (a
//  server, say) does not need this class at all: decode a `Hand` and give it
//  to `Handwriting`.
//
//  For a Spring person: a small singleton repository over one JSON file,
//  published to the views the way an observable bean would be. `@Published`
//  is what tells SwiftUI to redraw whoever is watching.
//

import Foundation
import SwiftUI

@MainActor
public final class HandStore: ObservableObject {
    /// The store most apps want: hand.json in Application Support, hand.json in the main bundle, HandKit's own.
    public static let shared = HandStore()

    @Published public private(set) var hand: Hand
    /// "By hand" or "typed" on the drawing page. Off means `active` is nil, whatever has been drawn.
    @Published public var enabled: Bool {
        didSet { UserDefaults.standard.set(!enabled, forKey: offKey) }
    }

    /// The hand to write with right now, or nil to show text another way.
    public var active: Hand? { enabled && !hand.isEmpty ? hand : nil }

    /// The saved file on this phone. Shared from the drawing page so it can be shipped in the app.
    public let fileURL: URL

    private let offKey: String
    /// The hand shipped inside the app, if there is one.
    private let shippedURL: URL?
    /// False when the app's Info.plist turns HandKit's own hand away.
    private let usesPackaged: Bool

    /// The hand to go back to when nothing has been drawn: the app's, or else HandKit's own.
    private var fallback: Hand? {
        shippedURL.flatMap { Hand(contentsOf: $0) } ?? (usesPackaged ? Hand.packaged : nil)
    }

    /// - Parameters:
    ///   - bundle: where the shipped hand is, and the Info.plist that may turn HandKit's own hand
    ///     away (`HandKitPackagedHand`). An app passes nothing; a package passes `.module`.
    ///   - name: the file's name without ".json". Change it to keep more than one hand.
    public init(bundle: Bundle = .main, name: String = "hand") {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = folder.appendingPathComponent("\(name).json")
        offKey = "\(name)Off"
        enabled = !UserDefaults.standard.bool(forKey: "\(name)Off")
        let shippedAt = bundle.url(forResource: name, withExtension: "json")
        shippedURL = shippedAt
        // A key that is not in the Info.plist reads as nil, which here means "yes".
        let packaged = bundle.object(forInfoDictionaryKey: "HandKitPackagedHand") as? Bool ?? true
        usesPackaged = packaged
        let shipped = shippedAt.flatMap { Hand(contentsOf: $0) } ?? (packaged ? Hand.packaged : nil)
        let drawn = Hand(contentsOf: fileURL).flatMap { $0.isEmpty ? nil : $0 }
        hand = drawn ?? shipped ?? Hand()
    }

    /// Adds one more drawing of a character.
    public func add(_ glyph: Glyph, for character: String) {
        hand.glyphs[character, default: []].append(glyph)
        save()
    }

    /// Forgets one drawing of a character: the one at that place in its list.
    public func remove(at index: Int, for character: String) {
        guard var drawings = hand.glyphs[character], drawings.indices.contains(index) else { return }
        drawings.remove(at: index)
        hand.glyphs[character] = drawings.isEmpty ? nil : drawings
        save()
    }

    /// Changes how often one drawing of a character is used.
    public func setFrequency(_ frequency: Glyph.Frequency, at index: Int, for character: String) {
        guard hand.glyphs[character]?.indices.contains(index) == true else { return }
        hand.glyphs[character]?[index].frequency = frequency
        save()
    }

    /// Replaces every drawing of a character with these. An empty list forgets it.
    public func set(_ glyphs: [Glyph], for character: String) {
        hand.glyphs[character] = glyphs.isEmpty ? nil : glyphs
        save()
    }

    /// Forgets every drawing of a character.
    public func forget(_ character: String) {
        hand.glyphs[character] = nil
        save()
    }

    /// Forgets every drawing: the hand is back to the one shipped in the app,
    /// or HandKit's own, or empty if there is neither. There is no undoing it,
    /// so ask first.
    public func reset() {
        hand = Hand()
        save()
        if let fallback { hand = fallback }
    }

    /// Replaces the hand with one from a file, such as letters drawn on an iPad
    /// and sent over. False if the file is not a hand.
    public func use(fileAt url: URL) -> Bool {
        // A file picked from outside the app is only readable between these two calls.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let picked = Hand(contentsOf: url), !picked.isEmpty else { return false }
        hand = picked
        save()
        return true
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = hand.data() {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension Hand {
    /// The hand HandKit carries: hand.json, beside this file. `HandStore` falls
    /// back on it; an app that keeps its hands some other way can use it too.
    /// Nil only if the file has gone missing from the package.
    ///
    /// `Bundle.module` is the package's own resources (the app's are
    /// `Bundle.main`). A `static let` is read once, the first time it is asked for.
    public static let packaged: Hand? = Bundle.module.url(forResource: "hand", withExtension: "json")
        .flatMap { Hand(contentsOf: $0) }
}
