import Foundation

/// Remembers the last playback position per stream, because Lampa's plain player templates
/// do not pass a resume position. Heuristic: keyed by the stream URL without TorrServer's
/// `play` / `preload` / `stat` flags. Capped so UserDefaults does not grow forever.
enum ResumeStore {
    private static let key = "resumePositions.v1"
    private static let maxEntries = 100

    private struct Entry: Codable { var key: String; var seconds: Double; var saved: Date }

    private static func normalized(_ url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        let drop: Set<String> = ["play", "preload", "stat"]
        comps.queryItems = comps.queryItems?.filter { !drop.contains($0.name.lowercased()) }
        if comps.queryItems?.isEmpty == true { comps.queryItems = nil }
        return comps.string ?? url.absoluteString
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    private static func store(_ entries: [Entry]) {
        let trimmed = Array(entries.sorted { $0.saved > $1.saved }.prefix(maxEntries))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func position(for url: URL) -> Double? {
        let k = normalized(url)
        return load().first { $0.key == k }?.seconds
    }

    static func save(_ seconds: Double, duration: Double, for url: URL) {
        let k = normalized(url)
        var entries = load().filter { $0.key != k }
        // Nothing to resume at the very start or in the last minute.
        let nearEnd = duration > 0 && seconds > duration - 60
        if seconds > 30, !nearEnd {
            entries.append(Entry(key: k, seconds: seconds, saved: Date()))
        }
        store(entries)
    }

    static func clear(for url: URL) {
        let k = normalized(url)
        store(load().filter { $0.key != k })
    }
}
