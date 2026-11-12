import SwiftUI
import HostDeps

/// Everything drawn on top of the video: subtitles, the transport rail, glass menus, info panes.
/// The video surface itself lives in the app root so it is always bound to the engine.
struct PlayerScreen: View {
    @ObservedObject var model: PlayerModel

    private var railVisible: Bool {
        switch model.mode {
        case .anchor, .tools, .menu: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            RemoteCatcher(model: model)

            SubtitleLayer(cues: model.visibleCues,
                          size: model.settings.v.subtitleSize.points,
                          lift: railVisible ? 200 : 0)
                .allowsHitTesting(false)

            if model.state == .loading || model.isBuffering || model.state == .seeking {
                ProgressView().scaleEffect(2.2)
            }

            if let err = model.loadError {
                VStack(spacing: 12) {
                    Text("Playback problem").font(.title2).bold()
                    Text(err).font(.callout).multilineTextAlignment(.center)
                    Text("Press Menu to go back").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(40)
                .glass(36)
                .padding(80)
            }

            if railVisible {
                RailView(model: model)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if case .menu = model.mode {
                MenuLayer(model: model)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }

            if case .pills(let index) = model.mode {
                PillsLayer(model: model, engine: model.engine, index: index)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 25, weight: .medium))
                            .padding(.horizontal, 28).padding(.vertical, 16)
                            .glass(40)
                    }
                    .padding(.horizontal, 80)
                    .padding(.bottom, 56)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.mode)
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}

/// Full-screen invisible view that receives every Siri Remote press. Wick does its own focus
/// handling (see `UIMode`), so there is only this one focusable view in the player.
private struct RemoteCatcher: View {
    @ObservedObject var model: PlayerModel
    @FocusState private var focused: Bool

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .focusable()
            .focused($focused)
            .onMoveCommand { model.move($0) }
            .onPlayPauseCommand { model.playPause() }
            .onExitCommand { model.menuButton() }
            .onTapGesture { model.select() }
            .onAppear { focused = true }
    }
}

// MARK: - Transport rail

private struct RailView: View {
    @ObservedObject var model: PlayerModel

    private var toolIndex: Int? {
        if case .tools(let i) = model.mode { return i }
        if case .menu = model.mode { return model.lastTool }
        return nil
    }

    var body: some View {
        let shown = model.scrubTime ?? model.currentTime
        let fraction = model.duration > 0 ? min(max(shown / model.duration, 0), 1) : 0
        let remaining = max(0, model.duration - shown)

        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(StreamInfo.summary(model.engine, model: model))
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Text(model.request?.displayTitle ?? "")
                            .font(.system(size: 57, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.leading, 4)
                    Spacer(minLength: 40)
                    HStack(spacing: 24) {
                        GlassCircleButton(systemName: "captions.bubble", focused: toolIndex == 0)
                        GlassCircleButton(systemName: "waveform", focused: toolIndex == 1)
                        GlassCircleButton(systemName: "slider.horizontal.3", focused: toolIndex == 2)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 40)

                Spacer().frame(height: 38)

                ScrubBar(fraction: fraction, scrubbing: model.scrubTime != nil)
                    .padding(.horizontal, 80)

                HStack {
                    Text(Self.format(shown))
                    Spacer()
                    Text("-" + Self.format(remaining))
                }
                .font(.system(size: 23, weight: .bold).monospacedDigit())
                .padding(.horizontal, 80)
                .padding(.top, 10)

                Spacer(minLength: 0)
            }
            .frame(height: 340)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 420)
                    .offset(y: 40)
            }
        }
        .ignoresSafeArea()
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ScrubBar: View {
    let fraction: Double
    let scrubbing: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.35, opacity: 0.55))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(14, geo.size.width * fraction))
            }
        }
        .frame(height: scrubbing ? 18 : 14)
        .animation(.easeOut(duration: 0.15), value: scrubbing)
    }
}

// MARK: - Glass menus

private struct MenuLayer: View {
    @ObservedObject var model: PlayerModel

    private let width: CGFloat = 520
    private let maxHeight: CGFloat = 560

    var body: some View {
        let kind = model.currentMenu ?? .subtitles
        let rows = model.rows(for: kind)
        let content = rows.reduce(CGFloat(0)) { $0 + $1.height }
        let height = min(maxHeight, 70 + content + 14)

        // Centre the popup over the tool button that opened it (buttons are 66 wide, 24 apart, 80 from the edge).
        let centreFromRight = 80 + 33 + CGFloat(2 - model.lastTool) * 90
        let trailing = max(40, centreFromRight - width / 2)

        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.title(for: kind))
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 34)
                        .frame(height: 70, alignment: .leading)

                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(rows) { row in
                                    MenuRowView(row: row, focused: row.id == model.menuFocus)
                                        .id(row.id)
                                }
                            }
                            .padding(.bottom, 14)
                        }
                        .onChange(of: model.menuFocus) { _, id in
                            if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
                        }
                    }
                }
                .frame(width: width, height: height)
                .glass(54)
                .padding(.trailing, trailing)
            }
            // The popup's bottom edge sits just above the tool row (rail top + 60, minus a gap).
            .padding(.bottom, 1080 - (1080 - 340 + 60) + 21)
        }
        .ignoresSafeArea()
    }
}

private struct MenuRowView: View {
    let row: MenuRow
    let focused: Bool

    var body: some View {
        switch row.kind {
        case .header:
            Text(row.title)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 34)
                .frame(height: row.height, alignment: .bottomLeading)
                .padding(.bottom, 6)

        case .separator:
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(height: 1)
                .padding(.horizontal, 28)
                .frame(height: row.height)

        case .option, .nav, .cycle:
            HStack(spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.system(size: 21, weight: .bold))
                    .opacity(row.selected ? 1 : 0)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 27, weight: .medium))
                        .lineLimit(1)
                    if let sub = row.subtitle {
                        Text(sub)
                            .font(.system(size: 23, weight: .medium))
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if row.kind == .cycle, let value = row.value {
                    Text(value)
                        .font(.system(size: 25, weight: .medium))
                        .opacity(0.7)
                }
                if row.kind == .nav {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 26, weight: .semibold))
                        .opacity(0.8)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 28)
            .frame(height: row.height - 6)
            .foregroundStyle(focused ? Color.black : Color.white.opacity(row.enabled ? 1 : 0.4))
            .background(Capsule().fill(focused ? Color.white : Color.clear))
            .scaleEffect(focused ? 1.02 : 1)
            .shadow(color: .black.opacity(focused ? 0.25 : 0), radius: 8, y: 5)
            .padding(.horizontal, 14)
            .frame(height: row.height)
            .animation(.easeOut(duration: 0.14), value: focused)

        case .stepper:
            HStack(spacing: 16) {
                Text(row.title)
                    .font(.system(size: 27, weight: .medium))
                    .padding(.leading, 66)
                Spacer(minLength: 8)
                StepperGlyph(symbol: "minus", focused: focused)
                Text(row.value ?? "")
                    .font(.system(size: 26, weight: .medium).monospacedDigit())
                    .frame(minWidth: 96)
                StepperGlyph(symbol: "plus", focused: focused)
            }
            .padding(.trailing, 28)
            .foregroundStyle(focused ? Color.black : Color.white)
            .frame(height: row.height - 6)
            .background(Capsule().fill(focused ? Color.white : Color.clear))
            .padding(.horizontal, 14)
            .frame(height: row.height)
            .animation(.easeOut(duration: 0.14), value: focused)
        }
    }
}

private struct StepperGlyph: View {
    let symbol: String
    let focused: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .bold))
            .frame(width: 58, height: 58)
            .foregroundStyle(focused ? Color.white : Color.white)
            .background(Circle().fill(focused ? Color.black.opacity(0.72) : Color.white.opacity(0.22)))
    }
}

// MARK: - Info and Details panes

private struct PillsLayer: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var engine: AetherEngine
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            HStack(spacing: 24) {
                GlassPill(title: "Info", focused: index == 0)
                GlassPill(title: "Details", focused: index == 1)
            }
            Group {
                if index == 0 {
                    InfoPane(model: model, engine: engine)
                } else {
                    DetailsPane(model: model, engine: engine)
                }
            }
            .frame(height: 280)
            .glass(48)
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 50)
        .ignoresSafeArea()
    }
}

private struct InfoPane: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var engine: AetherEngine

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            Image(systemName: "film.stack")
                .font(.system(size: 64, weight: .light))
                .frame(width: 150, height: 225)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.14)))

            VStack(alignment: .leading, spacing: 10) {
                Text(model.request?.displayTitle ?? "")
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(2)
                Text(model.request?.mediaURL.lastPathComponent.removingPercentEncoding ?? "")
                    .font(.system(size: 25, weight: .medium))
                    .opacity(0.75)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    ForEach(StreamInfo.chips(engine, model: model), id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 21, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.9), lineWidth: 2))
                    }
                }
            }
            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 6) {
                Text("Position")
                    .font(.system(size: 22, weight: .medium)).opacity(0.65)
                Text("\(RailTime.format(model.currentTime)) / \(RailTime.format(model.duration))")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
            }
        }
        .padding(30)
    }
}

private struct DetailsPane: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var engine: AetherEngine

    var body: some View {
        let video = StreamInfo.videoLines(engine)
        let audio = StreamInfo.audioLines(engine, model: model)
        let decode = StreamInfo.decodeLines(engine, model: model)
        HStack(alignment: .top, spacing: 40) {
            column("VIDEO", video)
            column("AUDIO", audio)
            column("DECODE / STREAM", decode)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 26)
    }

    private func column(_ header: String, _ lines: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Text(header)
                    .font(.system(size: 20, weight: .semibold))
                    .opacity(0.65)
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
            }
            .padding(.bottom, 4)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                (Text("\(line.0): ").font(.system(size: 21)).foregroundColor(.white.opacity(0.65))
                    + Text(line.1).font(.system(size: 24, weight: .medium)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum RailTime {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Reading stream facts from the engine

@MainActor
enum StreamInfo {
    static func resolution(_ e: AetherEngine) -> String? {
        let w = Int(e.sourceVideoWidth), h = Int(e.sourceVideoHeight)
        guard w > 0, h > 0 else { return nil }
        if w >= 3200 || h >= 2000 { return "4K" }
        if w >= 2400 { return "1440p" }
        if w >= 1800 { return "1080p" }
        if w >= 1200 { return "720p" }
        return "\(h)p"
    }

    static func formatName(_ f: VideoFormat) -> String {
        switch f {
        case .sdr: return "SDR"
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .dolbyVision: return "Dolby Vision"
        case .hlg: return "HLG"
        default: return String(describing: f)
        }
    }

    static func frameRate(_ e: AetherEngine) -> String? {
        guard let fps = e.sourceVideoFrameRate, fps > 0 else { return nil }
        let rounded = (fps * 1000).rounded() / 1000
        return String(format: "%gp", rounded)
    }

    static func bitrate(_ e: AetherEngine) -> String? {
        let b = e.sourceVideoBitrate
        guard b > 0 else { return nil }
        return b >= 100_000 ? String(format: "%.1f Mbps", Double(b) / 1_000_000) : "\(b) kbps"
    }

    static func summary(_ e: AetherEngine, model: PlayerModel) -> String {
        var parts: [String] = []
        if let r = resolution(e) { parts.append(r) }
        if e.videoFormat != .sdr { parts.append(formatName(e.videoFormat)) }
        if let c = e.sourceVideoCodecName { parts.append(c.uppercased()) }
        if let a = model.audioTracks.first(where: { $0.id == model.activeAudio }) {
            parts.append(model.trackDetail(a))
        }
        return parts.joined(separator: "  ·  ")
    }

    static func chips(_ e: AetherEngine, model: PlayerModel) -> [String] {
        var chips: [String] = []
        if let r = resolution(e) { chips.append(r) }
        chips.append(formatName(e.videoFormat))
        if let fps = frameRate(e) { chips.append(fps) }
        if model.audioTracks.first(where: { $0.id == model.activeAudio })?.isAtmos == true { chips.append("Atmos") }
        if !model.subtitleTracks.isEmpty { chips.append("CC") }
        return chips
    }

    static func videoLines(_ e: AetherEngine) -> [(String, String)] {
        var l: [(String, String)] = []
        l.append(("Mode", "Direct stream"))
        if let r = resolution(e) { l.append(("Format", "\(r) \(formatName(e.sourceVideoFormat))")) }
        if let c = e.sourceVideoCodecName { l.append(("Codec", c.uppercased())) }
        if let p = e.sourceDVProfile { l.append(("Dolby Vision", "Profile \(p)")) }
        if let conv = e.dolbyVisionConversion { l.append(("Playing as", String(describing: conv))) }
        if e.sourceVideoWidth > 0 { l.append(("Dimensions", "\(e.sourceVideoWidth) × \(e.sourceVideoHeight)")) }
        if let fps = frameRate(e) { l.append(("Frame rate", fps)) }
        if let b = bitrate(e) { l.append(("Bitrate", b)) }
        if let c = e.sourceContainerFormat { l.append(("Container", c)) }
        return l
    }

    static func audioLines(_ e: AetherEngine, model: PlayerModel) -> [(String, String)] {
        var l: [(String, String)] = []
        l.append(("Delivery", String(describing: e.audioDelivery)))
        for t in model.audioTracks.prefix(5) {
            let marker = t.id == model.activeAudio ? "▶ " : ""
            l.append((marker + model.trackTitle(t), model.trackDetail(t)))
        }
        if model.audioDelayMs != 0 { l.append(("Delay", "\(model.audioDelayMs) ms")) }
        l.append(("Atmos output", model.settings.v.atmos.short))
        return l
    }

    static func decodeLines(_ e: AetherEngine, model: PlayerModel) -> [(String, String)] {
        var l: [(String, String)] = []
        l.append(("Backend", String(describing: e.playbackBackend)))
        l.append(("Route", String(describing: e.videoRoute)))
        if let v = e.activeVideoDecoder { l.append(("Video decoder", v)) }
        if let a = e.activeAudioDecoder { l.append(("Audio decoder", a)) }
        l.append(("Seekable", e.isSourceSeekable.map { $0 ? "Yes" : "No" } ?? "Unknown"))
        l.append(("Buffering", model.isBuffering ? "Yes" : "No"))
        l.append(("FEL mode", model.settings.v.fel.short))
        return l
    }
}

// MARK: - Subtitles

private struct SubtitleLayer: View {
    let cues: [SubtitleCue]
    let size: CGFloat
    let lift: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 6) {
                    Spacer()
                    ForEach(cues.filter { $0.text != nil }) { cue in
                        Text((cue.text ?? "").replacingOccurrences(of: "\\N", with: "\n"))
                            .font(.system(size: size, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 3)
                            .shadow(color: .black, radius: 3)
                            .padding(.horizontal, 10)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.bottom, 80 + lift)
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.easeOut(duration: 0.25), value: lift)

                ForEach(cues) { cue in
                    if case .image(let image) = cue.body {
                        BitmapCue(image: image, container: geo.size)
                    }
                }
            }
        }
    }
}

/// PGS / DVB / DVD bitmap subtitle placed by its own coordinates inside the video canvas.
private struct BitmapCue: View {
    let image: SubtitleImage
    let container: CGSize

    var body: some View {
        let canvas = image.canvasSize == .zero ? CGSize(width: 1920, height: 1080) : image.canvasSize
        let scale = min(container.width / canvas.width, container.height / canvas.height)
        let originX = (container.width - canvas.width * scale) / 2
        let originY = (container.height - canvas.height * scale) / 2
        let rect = image.position

        Image(decorative: image.cgImage, scale: 1)
            .resizable()
            .frame(width: rect.width * scale, height: rect.height * scale)
            .position(x: originX + rect.midX * scale, y: originY + rect.midY * scale)
    }
}
