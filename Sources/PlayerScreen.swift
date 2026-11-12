import SwiftUI
import HostDeps

/// Everything drawn on top of the video: subtitles, transport bar, track panel.
/// The video surface itself lives in the app root so it is always bound to the engine.
struct PlayerScreen: View {
    @ObservedObject var model: PlayerModel
    @FocusState private var rootFocused: Bool

    var body: some View {
        ZStack {
            SubtitleLayer(cues: model.visibleCues, size: model.settings.v.subtitleSize.points)
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
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
                .padding(80)
            }

            if model.controlsVisible && !model.panelVisible {
                VStack {
                    Spacer()
                    TransportBar(model: model)
                }
            }

            if model.panelVisible {
                TrackPanel(model: model)
                    .onExitCommand { model.handleExit() }
            }
        }
        .focusable(!model.panelVisible)
        .focused($rootFocused)
        .onMoveCommand { direction in
            switch direction {
            case .left: model.skip(-1)
            case .right: model.skip(1)
            case .up, .down: model.openPanel()
            @unknown default: break
            }
        }
        .onPlayPauseCommand { model.togglePlayPause() }
        .onExitCommand { model.handleExit() }
        .onTapGesture { model.togglePlayPause() }
        .onAppear { rootFocused = true }
        .onChange(of: model.panelVisible) { _, visible in
            if !visible { rootFocused = true }
        }
    }
}

// MARK: - Transport bar

private struct TransportBar: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        let shown = model.scrubTime ?? model.currentTime
        let fraction = model.duration > 0 ? min(max(shown / model.duration, 0), 1) : 0

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.request?.displayTitle ?? "")
                    .font(.title3).bold().lineLimit(1)
                Spacer()
                Image(systemName: model.state == .playing ? "play.fill" : "pause.fill")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)

            HStack {
                Text(Self.format(shown))
                Spacer()
                Text(Self.format(model.duration))
            }
            .font(.callout.monospacedDigit())

            Text("◀ ▶ skip \(model.settings.v.skipSeconds)s     ▲ ▼ audio, subtitles and info     Play/Pause toggles")
                .font(.footnote).foregroundStyle(.secondary)

            if model.settings.v.showDebugInfo {
                ForEach(model.debugLines, id: \.self) { line in
                    Text(line).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 40)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        )
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Audio / subtitle panel

private struct TrackPanel: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    HStack(alignment: .top, spacing: 60) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Audio").font(.title2).bold()
                            ForEach(model.audioTracks) { track in
                                Button {
                                    model.selectAudio(track)
                                } label: {
                                    Label(model.label(for: track),
                                          systemImage: model.activeAudio == track.id ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Subtitles").font(.title2).bold()
                            Button {
                                model.subtitlesOff()
                            } label: {
                                Label("Off", systemImage: model.subtitleActive ? "circle" : "checkmark.circle.fill")
                            }
                            ForEach(model.subtitleTracks) { track in
                                Button {
                                    model.selectSubtitle(track)
                                } label: {
                                    Label(model.label(for: track),
                                          systemImage: model.subtitleActive && model.activeSubtitle == track.id
                                              ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }

                    Button {
                        model.reloadWithCurrentSettings()
                        model.panelVisible = false
                    } label: {
                        Label("Reload with current Settings (FEL, Atmos, audio...)", systemImage: "arrow.clockwise")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.debugLines, id: \.self) { line in
                            Text(line).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(80)
            }
        }
    }
}

// MARK: - Subtitles

private struct SubtitleLayer: View {
    let cues: [SubtitleCue]
    let size: CGFloat

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
                .padding(.bottom, 80)
                .frame(width: geo.size.width, height: geo.size.height)

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
