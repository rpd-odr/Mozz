#if os(iOS)
import Foundation
import Intents
import MozzCore
import MozzDatabase

/// Teaches the system what Mozz plays, so Siri gets better at it over time.
@MainActor
enum SiriMediaSuggestions {
    /// Whether this build was actually signed with com.apple.developer.siri.
    ///
    /// An unsigned/adhoc fork build has no usable Siri entitlement. SiriKit's
    /// INVocabulary throws an Objective-C exception instead of returning an error,
    /// so touching it in such a build would terminate the app.
    static let isAvailable: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let url = Bundle.main.url(forResource: "embedded",
                                        withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else {
            // Our unsigned IPA has no embedded provisioning profile.
            return false
        }

        // A .mobileprovision is CMS-signed binary with an XML plist embedded in it.
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8),
                                   in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: Data(data[start.lowerBound..<end.upperBound]),
                  options: [], format: nil
              ),
              let entitlements = (plist as? [String: Any])?["Entitlements"] as? [String: Any]
        else {
            return false
        }

        return entitlements["com.apple.developer.siri"] as? Bool ?? false
        #endif
    }()

    static func donate(_ resolution: MediaIntentResolution) {
        guard isAvailable else { return }

        let item = INMediaItem(identifier: resolution.subject.rawValue,
                               title: resolution.title,
                               type: resolution.type,
                               artwork: nil,
                               artist: resolution.artist)
        let isContainer: Bool
        switch resolution.type {
        case .song: isContainer = false
        default: isContainer = true
        }

        let intent = INPlayMediaIntent(
            mediaItems: isContainer ? nil : [item],
            mediaContainer: isContainer ? item : nil,
            playShuffled: resolution.prefersShuffle,
            playbackRepeatMode: .unknown,
            resumePlayback: false
        )
        intent.suggestedInvocationPhrase = "Play \(resolution.title) on Mozz"

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.identifier = resolution.subject.rawValue
        interaction.donate(completion: nil)
    }

    static func donatePlayedInApp(title: String, artist: String?,
                                  subject: MediaIntentSubject, type: INMediaItemType,
                                  shuffled: Bool = false) {
        donate(MediaIntentResolution(subject: subject, title: title, artist: artist,
                                     type: type, tracks: [], prefersShuffle: shuffled))
    }

    static func updateUserContext(libraryItemCount: Int?, isSignedIn: Bool) {
        guard isAvailable else { return }

        let context = INMediaUserContext()
        context.numberOfLibraryItems = libraryItemCount
        context.subscriptionStatus = isSignedIn ? .subscribed : .notSubscribed
        context.becomeCurrent()
    }

    static func registerVocabulary(playlists: [String], artists: [String]) {
        guard isAvailable else { return }

        #if targetEnvironment(simulator)
        return
        #else
        let playlists = Self.distinct(playlists, limit: 100)
        let artists = Self.distinct(artists, limit: 200)

        Task.detached(priority: .utility) {
            if !playlists.isEmpty {
                INVocabulary.shared().setVocabularyStrings(
                    NSOrderedSet(array: playlists),
                    of: .mediaPlaylistTitle
                )
            }
            if !artists.isEmpty {
                INVocabulary.shared().setVocabularyStrings(
                    NSOrderedSet(array: artists),
                    of: .mediaMusicArtistName
                )
            }
        }
        #endif
    }

    private static func distinct(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }
}
#endif
