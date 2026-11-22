//
//  Haptic.swift
//
//  The tactile side of the pen: a soft tick as each word starts, and a
//  firmer one when a drawing is kept.
//
//  UIKit's feedback generators are the lightest way to do this. `prepare()`
//  warms the Taptic Engine so the first tick is not late. Off iOS, and in
//  the simulator (which has no Taptic Engine and logs an error on every
//  call), these do nothing.
//

#if canImport(UIKit) && !targetEnvironment(simulator) && os(iOS)
import UIKit

@MainActor
enum Haptic {
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        selection.prepare()
    }

    static func tick() {
        selection.selectionChanged()
        selection.prepare()
    }

    static func success() {
        notification.notificationOccurred(.success)
    }
}
#else
@MainActor
enum Haptic {
    static func prepare() {}
    static func tick() {}
    static func success() {}
}
#endif
