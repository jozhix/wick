import SwiftUI
import Combine
import UIKit
import HostDeps

enum PlaybackOutcome { case success, cancel, failure }

/// Owns the one long-lived engine, mirrors its published state for SwiftUI,
/// and handles the Lampa hand-off (open a request, report back when done).
@MainActor
final class PlayerModel: ObservableObject {
    let engine: AetherEngine
    let settings = AppSettings()

    // Request / status
    @Published var request: PlayRequest?
    @Published var message: String?          // shown on the idle screen (bad link etc.)
    @Published var loadError: String?

    // Mirrored engine state
    @Published var state: PlaybackState = .idle
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering = false
    @Published var audioTracks: [TrackInfo] = []
    @Published var subtitleTracks: [TrackInfo] = []
    @Published var activeAudio: Int?
    @Published var activeSubtitle: Int?
    @Published var subtitleActive = false
    @Published var cues: [SubtitleCue] = []

    // UI state
    @Published var controlsVisible = true
    @Published var panelVisible = false
    @Published var scrubTime: Double?        // target while the user is skipping

    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var lastSeekPress = Date.distantPast
    private var seekPressCount = 0
    private var lastResumeSave = Date.distantPast

    init() {
        do {
            engine = try AetherEngine()
        } catch {
            fatalError("AetherEngine init failed: \(error)")
        }
        bind()
    }

    // MARK: - Engine -> UI

    private func bind() {
        engine.$state.receive(on: DispatchQueue.main).sink { [weak self] s in
            guard let self else { return }
            self.state = s
            switch s {
            case .ended:
                self.finish(.success)
            case .error(let text):
                self.loadError = text
            default:
                break
            }
        }.store(in: &bag)

        engine.clock.$currentTime.receive(on: DispatchQueue.main).sink { [weak self] t in
            guard let self else { return }
            self.currentTime = t
            if self.request != nil, Date().timeIntervalSince(self.lastResumeSave) > 10 {
                self.lastResumeSave = Date()
                self.saveResume()
            }
        }.store(in: &bag)

        engine.$duration.receive(on: DispatchQueue.main).assign(to: \.duration, on: self).store(in: &bag)
        engine.$isBuffering.receive(on: DispatchQueue.main).assign(to: \.isBuffering, on: self).store(in: &bag)
        engine.$audioTracks.receive(on: DispatchQueue.main).assign(to: \.audioTracks, on: self).store(in: &bag)
        engine.$subtitleTracks.receive(on: DispatchQueue.main).assign(to: \.subtitleTracks, on: self).store(in: &bag)
        engine.$activeAudioTrackIndex.receive(on: DispatchQueue.main).assign(to: \.activeAudio, on: self).store(in: &bag)
        engine.$activeSubtitleTrackIndex.receive(on: DispatchQueue.main).assign(to: \.activeSubtitle, on: self).store(in: &bag)
        engine.$isSubtitleActive.receive(on: DispatchQueue.main).assign(to: \.subtitleActive, on: self).store(in: &bag)
        engine.$subtitleCues.receive(on: DispatchQueue.main).assign(to: \.cues, on: self).store(in: &bag)
    }

    var visibleCues: [SubtitleCue] {
        guard subtitleActive else { return [] }
        let t = currentTime
        return cues.filter { $0.startTime <= t && t < $0.endTime }
    }

    // MARK: - Incoming links

    func handleIncoming(_ url: URL) {
        guard let req = PlayRequest.parse(url) else {
            message = "Could not find a stream address in this link:\n\(url.absoluteString)"
            return
        }
        message = nil
        open(req)
    }

    func open(_ req: PlayRequest) {
        loadTask?.cancel()
        seekTask?.cancel()
        request = req
        loadError = nil
        panelVisible = false
        scrubTime = nil
        currentTime = 0
        duration = 0
        controlsVisible = true

        var options = LoadOptions()
        settings.apply(to: &options)

        let saved = settings.v.resume ? ResumeStore.position(for: req.mediaURL) : nil
        let start = req.startPosition ?? saved
        let startPosition = (start ?? 0) > 5 ? start : nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.load(url: req.mediaURL, startPosition: startPosition, options: options)
                if Task.isCancelled { return }
                self.engine.play()
                if let sub = req.subtitleURL { self.engine.selectSidecarSubtitle(url: sub) }
                self.showControls()
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                self.loadError = "\(error)"
            }
        }
    }

    // MARK: - Controls

    func togglePlayPause() {
        engine.togglePlayPause()
        showControls()
    }

    func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        guard state == .playing, !panelVisible else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { self?.controlsVisible = false }
        }
    }

    func openPanel() {
        panelVisible = true
        controlsVisible = true
        hideTask?.cancel()
    }

    func handleExit() {
        if panelVisible {
            panelVisible = false
            showControls()
        } else {
            finish(loadError != nil ? .failure : .cancel)
        }
    }

    /// Skip forward/back. Quick repeated presses grow the step (x1, x1, x3, x3, x6).
    func skip(_ direction: Double) {
        let now = Date()
        seekPressCount = now.timeIntervalSince(lastSeekPress) < 0.7 ? seekPressCount + 1 : 0
        lastSeekPress = now
        let multipliers: [Double] = [1, 1, 3, 3, 6]
        let step = Double(settings.v.skipSeconds) * multipliers[min(seekPressCount, multipliers.count - 1)]

        var target = (scrubTime ?? currentTime) + direction * step
        target = max(0, target)
        if duration > 2 { target = min(target, duration - 2) }
        scrubTime = target
        showControls()

        seekTask?.cancel()
        seekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self, let t = self.scrubTime else { return }
            await self.engine.seek(to: t)
            self.scrubTime = nil
        }
    }

    func selectAudio(_ track: TrackInfo) { engine.selectAudioTrack(index: track.id) }
    func selectSubtitle(_ track: TrackInfo) { engine.selectSubtitleTrack(index: track.id) }
    func subtitlesOff() { engine.clearSubtitle() }

    /// Re-apply the current Settings to the playing session (route changes included).
    func reloadWithCurrentSettings() {
        let snapshot = settings
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.engine.reloadAtCurrentPosition { options in
                    snapshot.apply(to: &options)
                }
            } catch {
                self.loadError = "Reload failed: \(error)"
            }
        }
    }

    // MARK: - Leaving

    private func saveResume() {
        guard let req = request, currentTime > 0 else { return }
        ResumeStore.save(currentTime, duration: duration, for: req.mediaURL)
    }

    /// Stop playback and go back to the app that sent us here.
    func finish(_ outcome: PlaybackOutcome) {
        guard let req = request else { return }
        hideTask?.cancel()
        seekTask?.cancel()
        loadTask?.cancel()

        if outcome == .success {
            ResumeStore.clear(for: req.mediaURL)
        } else {
            saveResume()
        }
        engine.stop()

        let explicit: URL?
        switch outcome {
        case .success: explicit = req.onSuccess
        case .cancel: explicit = req.onCancel
        case .failure: explicit = req.onError
        }
        let target = explicit ?? defaultReturnURL(for: req)

        request = nil
        panelVisible = false
        scrubTime = nil
        if outcome == .failure, let err = loadError { message = "Playback failed: \(err)" }
        loadError = nil

        if let target {
            UIApplication.shared.open(target, options: [:], completionHandler: nil)
        }
    }

    private func defaultReturnURL(for req: PlayRequest) -> URL? {
        if let t = req.returnTarget, !t.isEmpty {
            return URL(string: t.contains("://") ? t : t + "://")
        }
        guard let scheme = settings.returnScheme else { return nil }
        return URL(string: scheme + "://")
    }

    // MARK: - Labels

    func label(for t: TrackInfo) -> String {
        var parts: [String] = [t.name.isEmpty ? "Track \(t.id)" : t.name]
        if let lang = t.language, !lang.isEmpty, !t.name.lowercased().contains(lang.lowercased()) {
            parts.append(lang.uppercased())
        }
        parts.append(t.codec.uppercased())
        if t.channels > 0 { parts.append("\(t.channels) ch") }
        if t.isAtmos { parts.append("Atmos") }
        if t.isDTSX { parts.append("DTS:X") }
        if t.isForced { parts.append("forced") }
        return parts.joined(separator: " · ")
    }

    var debugLines: [String] {
        [
            "backend \(String(describing: engine.playbackBackend))  route \(String(describing: engine.videoRoute))",
            "video \(String(describing: engine.videoFormat))  decoder \(engine.activeVideoDecoder ?? "-")",
            "audio \(String(describing: engine.audioDelivery))  decoder \(engine.activeAudioDecoder ?? "-")",
            "seekable \(String(describing: engine.isSourceSeekable))  buffering \(isBuffering)",
        ]
    }
}
