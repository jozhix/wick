import Foundation

/// What Lampa (or any x-callback-url style caller) asked us to play.
///
/// Lampa's Apple TV player templates (from `player.js`) all carry the stream as a
/// percent-encoded `url` query item, e.g.
///   SenPlayer://x-callback-url/play?url=<enc>
///   vlc-x-callback://x-callback-url/stream?url=<enc>
///   open-vidhub://x-callback-url/open?url=<enc>
/// Infuse links additionally carry `position`, `filename`, `sub`, `x-success`, `x-error`.
/// This parser accepts all of those plus our own `wick://play?...` form.
struct PlayRequest: Equatable {
    var mediaURL: URL
    var title: String?
    /// Seconds to start at, if the caller knows (Infuse-style links do).
    var startPosition: Double?
    var subtitleURL: URL?
    /// x-callback-url return addresses. Plain Lampa templates send none.
    var onSuccess: URL?
    var onError: URL?
    var onCancel: URL?
    /// Optional `return=<scheme or full URL>`: where to go back to when no x-* URL fits.
    var returnTarget: String?

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let name = mediaURL.lastPathComponent.removingPercentEncoding ?? mediaURL.lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let cleaned = stem.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return cleaned.isEmpty ? mediaURL.absoluteString : cleaned
    }

    static func parse(_ incoming: URL) -> PlayRequest? {
        guard let comps = URLComponents(url: incoming, resolvingAgainstBaseURL: false) else { return nil }

        // Query items are percent-decoded once here, which is exactly what Lampa's
        // encodeURIComponent(streamUrl) needs.
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            let key = item.name.lowercased()
            if let value = item.value, q[key] == nil { q[key] = value }
        }

        var media = q["url"] ?? q["src"] ?? q["link"] ?? q["stream"]

        // Raw style used by some players: vlc://http://host/file.mkv?x=y
        if media == nil {
            let s = incoming.absoluteString
            if let r = s.range(of: "://") {
                let rest = String(s[r.upperBound...])
                if rest.lowercased().hasPrefix("http") { media = rest }
            }
        }

        guard var mediaString = media?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mediaString.isEmpty else { return nil }

        // Lampa's TorrServer links end in `&preload` while preparing and `&play` to stream;
        // Lampa's own Infuse path rewrites preload -> play, so do the same.
        mediaString = mediaString.replacingOccurrences(of: "&preload", with: "&play")

        guard let mediaURL = makeURL(mediaString),
              let scheme = mediaURL.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else { return nil }

        var request = PlayRequest(mediaURL: mediaURL)
        request.title = q["title"] ?? q["filename"] ?? q["name"]
        request.startPosition = (q["position"] ?? q["start"] ?? q["t"]).flatMap { Double($0) }
        request.subtitleURL = (q["sub"] ?? q["subtitle"]).flatMap { makeURL($0) }
        request.onSuccess = q["x-success"].flatMap { makeURL($0) }
        request.onError = q["x-error"].flatMap { makeURL($0) }
        request.onCancel = q["x-cancel"].flatMap { makeURL($0) }
        request.returnTarget = q["return"]
        return request
    }

    private static func makeURL(_ string: String) -> URL? {
        if let url = URL(string: string) { return url }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "%#[]")
        return string.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: $0) }
    }
}
