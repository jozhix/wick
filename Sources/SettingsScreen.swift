import SwiftUI
import HostDeps

// Two-column settings in the style of a tvOS system app: a big icon tile and description on the
// left, capsule rows on the right, white capsule on focus. Layout numbers are in 1920 x 1080 points.

enum SettingsPage: Hashable {
    case root, playback, video, audio, subtitles, lampa, about
    // choice lists
    case dolbyVision, fel, atmos, bridge, audioLanguage, subtitleLanguage, returnTo

    var title: String {
        switch self {
        case .root: return "Settings"
        case .playback: return "Playback"
        case .video: return "Video"
        case .audio: return "Audio"
        case .subtitles: return "Subtitles"
        case .lampa: return "Lampa"
        case .about: return "About"
        case .dolbyVision: return "Dolby Vision"
        case .fel: return "Dolby Vision FEL"
        case .atmos: return "Height Speakers"
        case .bridge: return "Audio Bridge"
        case .audioLanguage: return "Audio Language"
        case .subtitleLanguage: return "Subtitle Language"
        case .returnTo: return "When Playback Ends"
        }
    }

    /// Choice lists borrow the look of the page they belong to.
    var family: SettingsPage {
        switch self {
        case .dolbyVision, .fel: return .video
        case .atmos, .bridge, .audioLanguage: return .audio
        case .subtitleLanguage: return .subtitles
        case .returnTo: return .lampa
        default: return self
        }
    }

    var symbol: String {
        switch family {
        case .playback: return "play.fill"
        case .video: return "tv"
        case .audio: return "hifispeaker.fill"
        case .subtitles: return "captions.bubble.fill"
        case .lampa: return "lamp.desk.fill"
        case .about: return "info"
        default: return "gearshape.fill"
        }
    }

    var color: Color {
        switch family {
        case .playback: return Color(red: 0.12, green: 0.45, blue: 1.0)
        case .video: return Color(red: 0.62, green: 0.34, blue: 1.0)
        case .audio: return Color(red: 1.0, green: 0.55, blue: 0.16)
        case .subtitles: return Color(red: 0.2, green: 0.78, blue: 0.7)
        case .lampa: return Color(red: 1.0, green: 0.78, blue: 0.25)
        case .about: return Color(white: 0.62)
        default: return Color(white: 0.7)
        }
    }

    var blurb: String {
        switch self {
        case .root: return "Wick plays streams that Lampa hands over. Settings apply to the next playback."
        case .playback: return "Skipping and resuming."
        case .video: return "Dolby Vision, FEL handling and upscaling."
        case .audio: return "Atmos height speakers, the audio bridge, delay and language."
        case .subtitles: return "Preferred language and size."
        case .lampa: return "Where playback returns to, and which Lampa player names this app answers to."
        case .about: return "Version, optional engine components and credits."
        case .dolbyVision: return "Use Dolby Vision where the display allows it, or always play the HDR10 base layer."
        case .fel: return "How Profile 7 FEL (dual-layer) streams are handled."
        case .atmos: return "TrueHD Atmos and DTS:X are rendered into this speaker layout. Pick what your receiver drives."
        case .bridge: return "How TrueHD, DTS, DTS-HD and Opus reach the receiver."
        case .audioLanguage: return "Chosen automatically when a stream starts."
        case .subtitleLanguage: return "Switched on automatically when a stream has this language."
        case .returnTo: return "Which app Wick opens when playback ends or you press Menu."
        }
    }
}

/// One line of a settings page.
private struct SItem: Identifiable {
    enum Kind {
        case header
        case nav(SettingsPage)
        case toggle(Bool, () -> Void)
        case cycle(() -> Void)
        case option(Bool, () -> Void)   // choice list entry: checkmark, select and go back
        case info
    }

    let id: String
    var kind: Kind
    var title: String
    var value: String? = nil
    var detail: String? = nil
    var dimmed = false
}

struct SettingsScreen: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var settings: AppSettings

    @State private var stack: [SettingsPage] = []
    @State private var focusMemory: [SettingsPage: String] = [:]
    @FocusState private var focusedRow: String?

    init(model: PlayerModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
    }

    private var page: SettingsPage { stack.last ?? .root }

    var body: some View {
        let items = self.items(for: page)
        let hint = items.first { $0.id == focusedRow }?.detail ?? page.blurb

        ZStack(alignment: .topLeading) {
            AmbientBackground(color: page.color)

            Text(page.title)
                .font(.system(size: 57, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.top, 52)

            // Left: tile + description
            VStack(spacing: 40) {
                RoundedRectangle(cornerRadius: 110, style: .continuous)
                    .fill(page.color.opacity(0.85))
                    .frame(width: 540, height: 540)
                    .overlay(
                        Image(systemName: page.symbol)
                            .font(.system(size: 200, weight: .medium))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)

                VStack(spacing: 14) {
                    Text(hint)
                        .font(.system(size: 29))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    if page == .root, let message = model.message {
                        Text(message)
                            .font(.system(size: 26))
                            .foregroundStyle(Color.orange)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                }
                .frame(width: 760)
            }
            .frame(width: 870)
            .padding(.leading, 90)
            .padding(.top, 180)

            // Right: rows
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
            }
            .frame(width: 828 + 48, alignment: .leading)
            .padding(.leading, 1036 - 24)
            .padding(.top, 150)
            .id(page)
            .transition(.opacity.combined(with: .offset(x: 72)))
        }
        .animation(.easeInOut(duration: 0.4), value: page)
        .onExitCommand(perform: stack.isEmpty ? nil : { pop() })
    }

    // MARK: Row drawing

    @ViewBuilder
    private func row(for item: SItem) -> some View {
        switch item.kind {
        case .header:
            Text(item.title.uppercased())
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 32)
                .padding(.top, 20)
                .padding(.bottom, 2)

        case .nav(let target):
            Button { push(target) } label: {
                RowLabel(title: item.title, value: item.value, chevron: true)
            }
            .buttonStyle(BareButtonStyle())
            .focused($focusedRow, equals: item.id)

        case .toggle(let on, let action):
            Button(action: action) {
                RowLabel(title: item.title, value: on ? "On" : "Off", dimmed: item.dimmed)
            }
            .buttonStyle(BareButtonStyle())
            .disabled(item.dimmed)
            .focused($focusedRow, equals: item.id)

        case .cycle(let action):
            Button(action: action) {
                RowLabel(title: item.title, value: item.value)
            }
            .buttonStyle(BareButtonStyle())
            .focused($focusedRow, equals: item.id)

        case .option(let selected, let action):
            Button {
                action()
                pop()
            } label: {
                RowLabel(title: item.title, value: item.value, checked: selected)
            }
            .buttonStyle(BareButtonStyle())
            .focused($focusedRow, equals: item.id)

        case .info:
            RowLabel(title: item.title, value: item.value, isInteractive: false)
        }
    }

    // MARK: Navigation

    private func push(_ target: SettingsPage) {
        if let id = focusedRow { focusMemory[page] = id }
        stack.append(target)
    }

    private func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        let restore = focusMemory[page]
        DispatchQueue.main.async { focusedRow = restore }
    }

    // MARK: Page contents

    private func items(for page: SettingsPage) -> [SItem] {
        let v = settings.v
        func set(_ change: @escaping (inout SettingValues) -> Void) -> () -> Void {
            { change(&settings.v) }
        }

        switch page {
        case .root:
            return [
                SItem(id: "playback", kind: .nav(.playback), title: "Playback"),
                SItem(id: "video", kind: .nav(.video), title: "Video"),
                SItem(id: "audio", kind: .nav(.audio), title: "Audio"),
                SItem(id: "subtitles", kind: .nav(.subtitles), title: "Subtitles"),
                SItem(id: "lampa", kind: .nav(.lampa), title: "Lampa"),
                SItem(id: "about", kind: .nav(.about), title: "About"),
            ]

        case .playback:
            return [
                SItem(id: "h.remote", kind: .header, title: "Remote"),
                SItem(id: "skip", kind: .cycle(set { s in
                    let all = [5, 10, 15, 30]
                    s.skipSeconds = all[((all.firstIndex(of: s.skipSeconds) ?? 1) + 1) % all.count]
                }), title: "Skip Forward and Back", value: "\(v.skipSeconds) seconds",
                      detail: "How far one press of left or right jumps. Quick repeats jump further."),
                SItem(id: "h.resume", kind: .header, title: "Resume"),
                SItem(id: "resume", kind: .toggle(v.resume, set { $0.resume.toggle() }),
                      title: "Resume Where I Stopped",
                      detail: "Wick remembers the position of each stream, because Lampa does not send one."),
            ]

        case .video:
            return [
                SItem(id: "h.dv", kind: .header, title: "Dolby Vision"),
                SItem(id: "dv", kind: .nav(.dolbyVision), title: "Dolby Vision",
                      value: v.dvHandling == .automatic ? "Auto" : "HDR10 only"),
                SItem(id: "fel", kind: .nav(.fel), title: "Dolby Vision FEL", value: v.fel.short,
                      detail: v.fel.detail),
                SItem(id: "h.home", kind: .header, title: "Home Theater"),
                SItem(id: "upscale", kind: .toggle(v.upscale, set { $0.upscale.toggle() }),
                      title: "Upscale SD and 720p",
                      detail: "Sharpens low-resolution video to the display size. Needs tvOS 26."),
                SItem(id: "lineart", kind: .toggle(v.upscaleLineArt, set { $0.upscaleLineArt.toggle() }),
                      title: "Line-Art Upscaler", detail: "A scaler made for animation. Only used while upscaling is on.",
                      dimmed: !v.upscale),
            ]

        case .audio:
            return [
                SItem(id: "h.out", kind: .header, title: "Home Theater"),
                SItem(id: "atmos", kind: .nav(.atmos), title: "Height Speakers", value: v.atmos.short,
                      detail: settings.v.atmos != .off && !settings.hasTrueHD
                          ? "This build has no TrueHD component, so TrueHD stays a plain channel decode."
                          : nil),
                SItem(id: "bridge", kind: .nav(.bridge), title: "Audio Bridge",
                      value: v.bridge == .surroundCompat ? "Compatible" : "Lossless"),
                SItem(id: "delay", kind: .cycle(set { s in
                    let all = [-300, -200, -100, -50, 0, 50, 100, 200, 300]
                    s.audioDelayMs = all[((all.firstIndex(of: s.audioDelayMs) ?? 4) + 1) % all.count]
                }), title: "Audio Delay", value: v.audioDelayMs == 0 ? "None" : "\(v.audioDelayMs) ms",
                      detail: "Lip-sync correction. You can also change it during playback."),
                SItem(id: "h.lang", kind: .header, title: "Language"),
                SItem(id: "alang", kind: .nav(.audioLanguage), title: "Audio Language", value: v.audioLanguage.label),
            ]

        case .subtitles:
            return [
                SItem(id: "slang", kind: .nav(.subtitleLanguage), title: "Subtitle Language",
                      value: v.subtitleLanguage == .none ? "Off" : v.subtitleLanguage.label),
                SItem(id: "ssize", kind: .cycle(set { $0.subtitleSize = Self.next($0.subtitleSize) }),
                      title: "Size", value: v.subtitleSize.label),
            ]

        case .lampa:
            var items: [SItem] = [
                SItem(id: "h.ret", kind: .header, title: "Return"),
                SItem(id: "ret", kind: .nav(.returnTo), title: "When Playback Ends", value: v.returnTo.short),
                SItem(id: "h.names", kind: .header, title: "Answers To"),
            ]
            for entry in RegisteredPlayers.current {
                items.append(SItem(id: "reg.\(entry.scheme)", kind: .info, title: entry.lampaName,
                                   value: entry.scheme + "://"))
            }
            return items

        case .about:
            let info = Bundle.main.infoDictionary
            let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
            let build = (info?["CFBundleVersion"] as? String) ?? "?"
            return [
                SItem(id: "ver", kind: .info, title: "Version", value: "\(version) (\(build))"),
                SItem(id: "h.comp", kind: .header, title: "Engine Components"),
                SItem(id: "c1", kind: .info, title: "Dual-Layer Dolby Vision", value: settings.hasDualLayer ? "In build" : "Missing"),
                SItem(id: "c2", kind: .info, title: "FEL Curves", value: settings.hasFelCurves ? "In build" : "Missing"),
                SItem(id: "c3", kind: .info, title: "TrueHD Atmos", value: settings.hasTrueHD ? "In build" : "Missing"),
                SItem(id: "c4", kind: .info, title: "DTS:X", value: settings.hasDTSX ? "In build" : "Missing"),
                SItem(id: "h.credits", kind: .header, title: "Made By"),
                SItem(id: "cr1", kind: .info, title: "Designed and built by", value: "jozhix"),
                SItem(id: "cr2", kind: .info, title: "Written with", value: "Claude (Anthropic)"),
                SItem(id: "cr3", kind: .info, title: "Playback engine", value: "AetherEngine, LGPL-3.0"),
                SItem(id: "cr4", kind: .info, title: "Look inspired by", value: "Rivulet"),
            ]

        // MARK: choice lists
        case .dolbyVision:
            return DVHandlingChoice.allCases.map { c in
                SItem(id: "dv.\(c.rawValue)", kind: .option(v.dvHandling == c, set { $0.dvHandling = c }), title: c.label)
            }
        case .fel:
            return FELChoice.allCases.map { c in
                SItem(id: "fel.\(c.rawValue)", kind: .option(v.fel == c, set { $0.fel = c }), title: c.label, detail: c.detail)
            }
        case .atmos:
            return AtmosChoice.allCases.map { c in
                SItem(id: "atmos.\(c.rawValue)", kind: .option(v.atmos == c, set { $0.atmos = c }), title: c.label)
            }
        case .bridge:
            return BridgeChoice.allCases.map { c in
                SItem(id: "bridge.\(c.rawValue)", kind: .option(v.bridge == c, set { $0.bridge = c }), title: c.label)
            }
        case .audioLanguage:
            return LangChoice.allCases.map { c in
                SItem(id: "al.\(c.rawValue)", kind: .option(v.audioLanguage == c, set { $0.audioLanguage = c }), title: c.label)
            }
        case .subtitleLanguage:
            return LangChoice.allCases.map { c in
                SItem(id: "sl.\(c.rawValue)", kind: .option(v.subtitleLanguage == c, set { $0.subtitleLanguage = c }),
                      title: c == .none ? "Off" : c.label)
            }
        case .returnTo:
            return ReturnChoice.allCases.map { c in
                SItem(id: "rt.\(c.rawValue)", kind: .option(v.returnTo == c, set { $0.returnTo = c }), title: c.label)
            }
        }
    }

    private static func next<T: CaseIterable & Equatable>(_ value: T) -> T {
        let all = Array(T.allCases)
        guard let i = all.firstIndex(of: value) else { return value }
        return all[(i + 1) % all.count]
    }
}

extension ReturnChoice {
    var short: String {
        switch self {
        case .lampa: return "Lampa"
        case .luxo: return "Luxo"
        case .none: return "Stay here"
        }
    }
}

// MARK: - Look

/// A capsule row. Focus is read from the surrounding Button.
private struct RowLabel: View {
    @Environment(\.isFocused) private var focused

    let title: String
    var value: String? = nil
    var chevron = false
    var checked = false
    var dimmed = false
    var isInteractive = true

    var body: some View {
        let on = focused && isInteractive
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 36, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(on ? Color.black.opacity(0.45) : Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(on ? Color.black.opacity(0.45) : Color.white.opacity(0.4))
            }
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.blue)
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 66)
        .foregroundStyle(on ? Color.black : Color.white)
        .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.10)))
        .scaleEffect(on ? 1.055 : 1)
        .shadow(color: .black.opacity(on ? 0.3 : 0), radius: 10, y: 6)
        .opacity(dimmed ? 0.35 : 1)
        .padding(.vertical, 3)
        .animation(.easeOut(duration: 0.16), value: on)
    }
}

/// Black with a soft coloured wash, like an artwork-tinted tvOS backdrop.
private struct AmbientBackground: View {
    let color: Color

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [color.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 1300)
            RadialGradient(colors: [Color(red: 0.1, green: 0.25, blue: 0.9).opacity(0.35), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 1100)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: color)
    }
}
