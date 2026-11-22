//
//  HandStore.swift
//
//  Where a hand lives on the phone.
//
//  Two places, looked in this order:
//
//    1. hand.json in the app's Application Support folder: letters drawn on
//       this device with HandEditor. If there are any, they win, so you see
//       your work as you draw.
//    2. hand.json shipped inside the app (in its bundle): the hand everybody
//       gets.
//
//  If neither exists the hand is empty and `active` is nil: the app should
//  show its text some other way.
//
//  To ship a hand: draw it in HandEditor, tap "send my hand as a file", and
//  add the file to the app target as hand.json.
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
    /// The store most apps want: hand.json in the main bundle, hand.json in Application Support.
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

    /// - Parameters:
    ///   - bundle: where the shipped hand is. An app passes nothing; a package passes `.module`.
    ///   - name: the file's name without ".json". Change it to keep more than one hand.
    public init(bundle: Bundle = .main, name: String = "hand") {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = folder.appendingPathComponent("\(name).json")
        offKey = "\(name)Off"
        enabled = !UserDefaults.standard.bool(forKey: "\(name)Off")
        let shipped = bundle.url(forResource: name, withExtension: "json").flatMap { Hand(contentsOf: $0) }
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

    /// Forgets every drawing of a character.
    public func forget(_ character: String) {
        hand.glyphs[character] = nil
        save()
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
