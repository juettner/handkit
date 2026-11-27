//
//  Publish.swift
//
//  "Publish": sending the hand to a server, when you say so.
//
//  Drawing a letter never sends anything anywhere. The hand is saved on this
//  device as you draw, and that is all. Publishing is a button, with a
//  question after it, and it does one thing: it sends the whole hand, as it
//  is now, to the one server you have named. An app that reads its
//  handwriting from that server (P.S. does) then writes every new note in
//  this hand. Notes already written keep the hand they were written in.
//
//  It is behind "developer tools" because it needs two things most people
//  will never have: the address of such a server, and its publishing key.
//
//    HandPublisher   where the address and the key live, and the one request.
//    PublishPart   the part of the Keep page that asks for them.
//
//  The key is a secret, so it goes in the Keychain (the phone's own safe for
//  passwords) and not in the app's ordinary settings. The address is not a
//  secret and is an ordinary setting.
//
//  For a Java person: `HandPublisher` is a small @Service with a RestTemplate
//  call in it; `PublishPart` is the form in front of it.
//

import CryptoKit
import HandKit
import Security
import SwiftUI

/// What became of an attempt to publish.
enum PublishOutcome: Equatable {
    /// The server took it. `drawings` is how many keys the hand has, as the server counted them; `isNew` is false when that very hand had been published before.
    case done(drawings: Int, isNew: Bool)
    case failed(String)

    var sentence: String {
        switch self {
        case .done(let drawings, let isNew):
            return isNew
                ? "Published: \(drawings) drawings. New notes are written in this hand."
                : "Published again: this hand had been published before, and is the current one once more."
        case .failed(let why):
            return why
        }
    }
}

enum HandPublisher {
    /// The name the key is kept under in the Keychain.
    private static let service = "com.juettner.handkit.publish"
    private static let account = "key"

    /// The publishing key, or an empty string if none has been typed in.
    static var key: String {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var found: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        set {
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            // Taken out and put back: simpler than asking whether it is there, and an empty key is simply taken out.
            SecItemDelete(item as CFDictionary)
            guard !newValue.isEmpty else { return }
            var fresh = item
            fresh[kSecValueData as String] = Data(newValue.utf8)
            // Readable only while the device is unlocked, and never copied to another device with a backup.
            fresh[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(fresh as CFDictionary, nil)
        }
    }

    /// Where a hand is sent, given what was typed: "ps.example.com" and
    /// "https://ps.example.com/" both mean https://ps.example.com/api/hand.
    /// Nil if what was typed is not an address. Only https: the key travels with the request.
    static func endpoint(for typed: String) -> URL? {
        var address = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return nil }
        if !address.contains("://") { address = "https://" + address }
        while address.hasSuffix("/") { address.removeLast() }
        guard let url = URL(string: address), url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url.appendingPathComponent("api").appendingPathComponent("hand")
    }

    /// A short mark of a hand, for telling whether it has changed since it was
    /// published. (The server works out its own id for a hand; this one is
    /// only ever compared with itself.)
    static func mark(of hand: Hand) -> String {
        guard let data = hand.data() else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Sends the hand. The one place in the app where anything leaves the device without a share sheet.
    static func publish(_ hand: Hand, to typed: String, key: String) async -> PublishOutcome {
        guard let url = endpoint(for: typed) else { return .failed("That is not an address a hand can be sent to. It looks like ps.example.com.") }
        guard !key.isEmpty else { return .failed("The publishing key is missing.") }
        guard let body = hand.data(), !hand.isEmpty else { return .failed("There is no hand to publish yet.") }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200...299:
                let answer = try? JSONDecoder().decode(Answer.self, from: data)
                return .done(drawings: answer?.glyphs ?? hand.glyphs.count, isNew: answer?.isNew ?? true)
            case 401:
                return .failed("The server did not take the key. Nothing was published.")
            case 404:
                return .failed("That server does not take hands, or publishing is switched off there. Nothing was published.")
            case 400:
                // The server says what is wrong with the hand in a sentence of its own.
                let said = (try? JSONDecoder().decode(Refusal.self, from: data))?.message
                return .failed("The server refused this hand\(said.map { ": \($0)" } ?? "."). Nothing was published.")
            case 413:
                return .failed("This hand is too large for the server to take. Nothing was published.")
            default:
                return .failed("The server answered \(status). Nothing was published.")
            }
        } catch {
            return .failed("The server could not be reached. Nothing was published.")
        }
    }

    /// What the server says when it takes a hand.
    private struct Answer: Decodable {
        let glyphs: Int?
        let isNew: Bool?
    }

    /// What it says when it does not. `message` is a sentence, or now and then a list of them.
    private struct Refusal: Decodable {
        let message: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let one = try? container.decode(String.self, forKey: .message) {
                message = one
            } else {
                message = (try? container.decode([String].self, forKey: .message))?.first
            }
        }

        private enum CodingKeys: String, CodingKey { case message }
    }
}

/// The part of the Keep page that publishes. Shown with "developer tools" on.
struct PublishPart: View {
    @ObservedObject private var hands = HandStore.shared
    /// The server's address, as typed. An ordinary setting.
    @AppStorage("publishAddress") private var address = ""
    /// The mark of the hand that was published last from this device, and when.
    @AppStorage("publishedMark") private var publishedMark = ""
    @AppStorage("publishedAt") private var publishedAt = 0.0

    @State private var key = ""
    @State private var asking = false
    @State private var sending = false
    @State private var outcome: PublishOutcome? = nil

    private var ready: Bool {
        !hands.hand.isEmpty && HandPublisher.endpoint(for: address) != nil && !key.isEmpty && !sending
    }

    /// Where things stand: never published, published and unchanged, or changed since.
    private var standing: String {
        guard !publishedMark.isEmpty else { return "This hand has not been published from this device." }
        let when = Date(timeIntervalSince1970: publishedAt).formatted(date: .abbreviated, time: .shortened)
        return publishedMark == HandPublisher.mark(of: hands.hand)
            ? "Published \(when). Nothing has changed since."
            : "Published \(when). You have drawn since: what is published is the hand as it was then."
    }

    var body: some View {
        Part("Publish") {
            Note("Send this hand to a server that an app reads its handwriting from. Nothing is sent as you draw: only when you publish. Every note written after that is in this hand, and notes written before keep the one they had.")
            field("Server") {
                TextField("ps.example.com", text: $address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
            }
            field("Publishing key") {
                SecureField("The server's key", text: $key)
                    .textContentType(.password)
            }
            Button(sending ? "Publishing..." : "Publish my hand") { asking = true }
                .buttonStyle(PrimaryButton())
                .disabled(!ready)
                .opacity(ready ? 1 : 0.45)
            Note(standing)
            if let outcome {
                Note(outcome.sentence)
            }
        }
        .onAppear { key = HandPublisher.key }
        // Kept as it is typed, so it is there the next time without a Save button.
        .onChange(of: key) { _, typed in
            if typed != HandPublisher.key { HandPublisher.key = typed }
        }
        .alert("Publish this hand?", isPresented: $asking) {
            Button("Publish") { send() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every new note will be written in it. Notes already written are not changed.")
        }
    }

    /// A labelled line to type on, in the app's own type.
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.serif(.footnote))
                .foregroundStyle(Theme.grey)
            content()
                .font(Theme.serif(.body))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 8)
            Rectangle()
                .fill(Theme.edge)
                .frame(height: 1)
        }
    }

    private func send() {
        // The hand as it is at this moment: what is drawn while the request is on its way is not part of it.
        let hand = hands.hand
        sending = true
        outcome = nil
        Task {
            let result = await HandPublisher.publish(hand, to: address, key: key)
            if case .done = result {
                publishedMark = HandPublisher.mark(of: hand)
                publishedAt = Date().timeIntervalSince1970
            }
            outcome = result
            sending = false
        }
    }
}
