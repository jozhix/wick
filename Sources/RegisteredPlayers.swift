import Foundation

/// Reads the URL schemes this installed build answers to (Info.plist, CFBundleURLTypes)
/// and names them the way Lampa's Apple TV player setting does.
enum RegisteredPlayers {
    struct Entry {
        let scheme: String
        let lampaName: String
    }

    private static let lampaNames: [String: String] = [
        "vlc-x-callback": "VLC",
        "infuse": "Infuse",
        "senplayer": "SenPlayer",
        "open-vidhub": "VidHub",
        "svplayer": "SVPlayer",
        "wick": "Own link form",
    ]

    static var current: [Entry] {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        return schemes.map { Entry(scheme: $0, lampaName: lampaNames[$0.lowercased()] ?? $0) }
    }
}
