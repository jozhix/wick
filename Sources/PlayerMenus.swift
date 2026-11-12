import SwiftUI
import HostDeps

/// One line in a glass menu. Menus are rebuilt from the model's state every time they are drawn,
/// so a row never shows stale values.
struct MenuRow: Identifiable {
    enum Kind { case header, separator, option, nav, cycle, stepper }

    let id: String
    var kind: Kind
    var title: String = ""
    var subtitle: String? = nil
    var value: String? = nil
    var selected = false
    var enabled = true
    var select: (() -> Void)? = nil
    var adjust: ((Int) -> Void)? = nil

    var focusable: Bool { enabled && kind != .header && kind != .separator }

    var height: CGFloat {
        switch kind {
        case .header: return 56
        case .separator: return 22
        case .stepper: return 76
        default: return subtitle == nil ? 66 : 88
        }
    }
}

// Short labels for the in-player "Playback" menu.
extension FELChoice {
    var short: String {
        switch self {
        case .off: return "Off"
        case .curves: return "FEL curves"
        case .dualLayerSoftware: return "Dual-layer"
        case .dualLayerAVPlayer: return "Dual-layer (AVPlayer)"
        }
    }
}

extension AtmosChoice {
    var short: String {
        switch self {
        case .off: return "Off"
        case .l512: return "5.1.2"
        case .l514: return "5.1.4"
        case .l712: return "7.1.2"
        case .l714: return "7.1.4"
        case .l916: return "9.1.6"
        }
    }
}

private func nextCase<T: CaseIterable & Equatable>(_ value: T) -> T {
    let all = Array(T.allCases)
    guard let i = all.firstIndex(of: value) else { return value }
    return all[(i + 1) % all.count]
}

extension PlayerModel {

    func title(for kind: MenuKind) -> String {
        switch kind {
        case .subtitles: return "Subtitles"
        case .subtitleLanguage: return "Subtitle Language"
        case .audio: return "Audio"
        case .playback: return "Playback"
        }
    }

    func rows(for kind: MenuKind) -> [MenuRow] {
        switch kind {
        case .subtitles: return subtitleRows()
        case .subtitleLanguage: return subtitleLanguageRows()
        case .audio: return audioRows()
        case .playback: return playbackRows()
        }
    }

    // MARK: Subtitles

    private func subtitleRows() -> [MenuRow] {
        let hasTracks = !subtitleTracks.isEmpty
        let current = subtitleTracks.first { $0.id == activeSubtitle }.map(trackTitle) ?? (hasTracks ? "None" : "No subtitle tracks")
        return [
            MenuRow(id: "sub.on", kind: .option, title: "On", selected: subtitleActive, enabled: hasTracks,
                    select: { self.subtitlesOn() }),
            MenuRow(id: "sub.off", kind: .option, title: "Off", selected: !subtitleActive,
                    select: { self.subtitlesOff() }),
            MenuRow(id: "sep.sub1", kind: .separator),
            MenuRow(id: "sub.lang", kind: .nav, title: "Language", subtitle: current, enabled: hasTracks,
                    select: { self.pushMenu(.subtitleLanguage) }),
            MenuRow(id: "sub.size", kind: .cycle, title: "Size", value: settings.v.subtitleSize.label,
                    select: { self.settings.v.subtitleSize = nextCase(self.settings.v.subtitleSize) }),
            MenuRow(id: "sep.sub2", kind: .separator),
            MenuRow(id: "sub.delay", kind: .stepper, title: "Delay", value: String(format: "%.1fs", subtitleDelay),
                    adjust: { d in self.setSubtitleDelay(self.subtitleDelay + 0.1 * Double(d)) }),
        ]
    }

    private func subtitleLanguageRows() -> [MenuRow] {
        if subtitleTracks.isEmpty {
            return [MenuRow(id: "sub.none", kind: .option, title: "No subtitle tracks", enabled: false)]
        }
        return subtitleTracks.map { track in
            MenuRow(id: "sub.\(track.id)", kind: .option, title: trackTitle(track), subtitle: trackDetail(track),
                    selected: subtitleActive && activeSubtitle == track.id,
                    select: {
                        self.selectSubtitle(track)
                        self.popMenu()
                    })
        }
    }

    // MARK: Audio

    private func audioRows() -> [MenuRow] {
        var rows: [MenuRow] = [
            MenuRow(id: "aud.delay", kind: .stepper, title: "Delay", value: "\(audioDelayMs) ms",
                    adjust: { d in self.setAudioDelay(ms: self.audioDelayMs + 50 * d) }),
            MenuRow(id: "sep.aud1", kind: .separator),
            MenuRow(id: "hdr.tracks", kind: .header, title: "Audio Track"),
        ]
        for track in audioTracks {
            rows.append(MenuRow(id: "aud.\(track.id)", kind: .option, title: trackTitle(track), subtitle: trackDetail(track),
                                selected: activeAudio == track.id,
                                select: { self.selectAudio(track) }))
        }
        if audioTracks.isEmpty {
            rows.append(MenuRow(id: "aud.none", kind: .option, title: "No audio tracks", enabled: false))
        }
        return rows
    }

    // MARK: Playback (speed and the engine settings that matter most)

    private func playbackRows() -> [MenuRow] {
        let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        let speedLabel = speed == 1.0 ? "Normal" : String(format: "%gx", speed)
        return [
            MenuRow(id: "pb.speed", kind: .cycle, title: "Speed", value: speedLabel,
                    select: {
                        let i = speeds.firstIndex(of: self.speed) ?? 1
                        self.setSpeed(speeds[(i + 1) % speeds.count])
                    }),
            MenuRow(id: "sep.pb1", kind: .separator),
            MenuRow(id: "pb.fel", kind: .cycle, title: "Dolby Vision FEL", value: settings.v.fel.short,
                    select: { self.settings.v.fel = nextCase(self.settings.v.fel) }),
            MenuRow(id: "pb.atmos", kind: .cycle, title: "Height Speakers", value: settings.v.atmos.short,
                    select: { self.settings.v.atmos = nextCase(self.settings.v.atmos) }),
            MenuRow(id: "pb.upscale", kind: .cycle, title: "Upscale SD and 720p", value: settings.v.upscale ? "On" : "Off",
                    select: { self.settings.v.upscale.toggle() }),
            MenuRow(id: "sep.pb2", kind: .separator),
            MenuRow(id: "pb.apply", kind: .option, title: "Apply changes now", subtitle: "Reloads at the current position",
                    select: {
                        self.reloadWithCurrentSettings()
                        self.closeMenus()
                    }),
        ]
    }

    // MARK: Labels

    func trackTitle(_ t: TrackInfo) -> String {
        if let lang = t.language, !lang.isEmpty,
           let name = Locale.current.localizedString(forLanguageCode: lang) {
            return name
        }
        return t.name.isEmpty ? "Track \(t.id)" : t.name
    }

    func trackDetail(_ t: TrackInfo) -> String {
        var parts: [String] = []
        if !t.name.isEmpty, t.name != trackTitle(t) { parts.append(t.name) }
        parts.append(t.codec.uppercased())
        if t.channels > 0 { parts.append(Self.channelLabel(t.channels)) }
        if t.isAtmos { parts.append("Atmos") }
        if t.isDTSX { parts.append("DTS:X") }
        if t.isForced { parts.append("Forced") }
        return parts.joined(separator: " ")
    }

    static func channelLabel(_ n: Int) -> String {
        switch n {
        case 1: return "1.0"
        case 2: return "2.0"
        case 3: return "2.1"
        case 4: return "4.0"
        case 5: return "5.0"
        case 6: return "5.1"
        case 7: return "6.1"
        case 8: return "7.1"
        default: return "\(n)ch"
        }
    }
}
