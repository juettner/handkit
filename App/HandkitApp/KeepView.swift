//
//  KeepView.swift
//
//  "Keep": the hand as a file, in and out, and the few things to know.
//
//  A hand is one small file (hand.json). Sending it somewhere is the backup,
//  and opening it on another device is how a hand drawn on an iPad with a
//  Pencil gets onto a phone. There is no account and no server in between:
//  the file goes wherever the share sheet sends it.
//
//  With developer tools on there is one more way out: publishing the hand to
//  a server of your own (Publish.swift). That, too, only happens when asked.
//
//  Bringing a file in replaces the letters on this device, and so does
//  starting over, so both ask first.
//

import HandKit
import SwiftUI
import UniformTypeIdentifiers

struct KeepView: View {
    @ObservedObject private var hands = HandStore.shared
    @AppStorage("developer") private var developer = false

    @State private var picking = false
    @State private var askingToReplace = false
    @State private var askingToStartOver = false
    /// What happened to the file that was brought in.
    @State private var fileNote: String? = nil

    /// "1.0 (3)": the version people see, and the build number.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    var body: some View {
        Page("Keep") {
            Part("Back it up") {
                Note("Your hand is one small file. Send it to yourself, save it to Files, or AirDrop it to another device.")
                ShareLink(item: hands.fileURL) {
                    Text("Send my hand")
                }
                .buttonStyle(PrimaryButton())
                .disabled(hands.hand.isEmpty)
                .opacity(hands.hand.isEmpty ? 0.45 : 1)
            }

            Part("Bring one in") {
                Note("Open a hand file from another device. It takes the place of the letters on this one.")
                Button("Open a hand file") {
                    // With letters here already, ask before they are replaced.
                    if hands.hand.isEmpty { picking = true } else { askingToReplace = true }
                }
                .buttonStyle(SecondaryButton())
                if let fileNote {
                    Note(fileNote)
                }
            }

            Part("Start over") {
                Note("Forget every letter, scribble and signature on this device. Send your hand somewhere first if you might want it back.")
                Button("Forget my hand") { askingToStartOver = true }
                    .buttonStyle(WordButton(color: Theme.heart))
                    .disabled(hands.hand.isEmpty)
                    .opacity(hands.hand.isEmpty ? 0.45 : 1)
            }

            Rule()

            Part("For developers") {
                Toggle(isOn: $developer) {
                    Text("Developer tools")
                        .font(Theme.serif(.body))
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.ink)
                Note("Adds to the drawing page what an app built on HandKit needs: pictures kept under a name, an app icon, and the hand file within reach. And, below, publishing the hand to a server.")
            }

            // Sending the hand to a server an app reads it from: see Publish.swift.
            if developer {
                PublishPart()
            }

            Part("About") {
                Note("Handkit \(version)")
                Note("Your handwriting is kept on this device. Handkit has no account, no server of its own and no analytics, and nothing leaves the device unless you send it.")
            }
        }
        // An alert is the small box in the middle of the screen, on a phone and
        // on an iPad alike.
        .alert("Replace the letters on this device?", isPresented: $askingToReplace) {
            Button("Choose a file", role: .destructive) {
                // One page at a time: the file picker comes up once the alert has gone.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    picking = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The hand in the file takes the place of the one here. This cannot be undone.")
        }
        .alert("Forget every letter you have drawn?", isPresented: $askingToStartOver) {
            Button("Forget my hand", role: .destructive) {
                hands.reset()
                fileNote = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            fileNote = hands.use(fileAt: url) ? "Now writing in that hand." : "That file is not a hand."
        }
    }
}
