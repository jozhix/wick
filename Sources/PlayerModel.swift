import SwiftUI
import Combine
import UIKit
import HostDeps

enum PlaybackOutcome { case success, cancel, failure }

/// What the Siri Remote is currently driving. Wick handles focus itself (one invisible
/// focusable view receives every press), so these modes are the whole navigation model.
enum UIMode: Equatable {
    case hidden            // video only
    case anchor            // transport bar shown, left/right skip
    case tools(Int)        // bottom-right round buttons: 0 subtitles, 1 audio, 2 playback
    case pills(Int)        // Info / Details panes: 0 info, 1 details
    case menu              // a glass menu is open (see menuStack)
}

enum MenuKind: Equatable {
    case subtitles, subtitleLanguage, audio, playback
}

/// Owns the one long-lived engine, mirrors its published state for SwiftUI,
/// handles remote input, and handles the Lampa hand-off.
@MainActor
final class PlayerModel: ObservableObject {
    let engine: AetherEngine
    let settings = AppSettings()

    // Request / status
    @Published var request: PlayRequest?
    @Published var message: String?          // shown on the settings screen (bad link etc.)
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
    @Published var mode: UIMode = .anchor
    @Published var menuStack: [MenuKind] = []
    @Published var menuFocus: String?
    @Published var scrubTime: Double?        // target while the user is skipping
    @Published var subtitleDelay = 0.0       // seconds
    @Published var audioDelayMs = 0
    @Published var speed: Float = 1.0
    @Published var toast: String?

    var lastTool = 0
    var lastSubtitleID: Int?

    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
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
            case .playing:
                self.touch()
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
        menuStack = []
        menuFocus = nil
        scrubTime = nil
        currentTime = 0
        duration = 0
        subtitleDelay = 0
        audioDelayMs = settings.v.audioDelayMs
        speed = 1.0
        lastSubtitleID = nil
        mode = .anchor

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
                self.touch()
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                self.loadError = "\(error)"
            }
        }
    }

    // MARK: - Remote input (everything funnels through these four)

    func move(_ direction: MoveCommandDirection) {
        switch mode {
        case .hidden, .anchor:
            switch direction {
            case .left: skip(-1)
            case .right: skip(1)
            case .up: mode = .tools(lastTool)
            case .down: mode = .pills(0)
            @unknown default: break
            }
        case .tools(let i):
            switch direction {
            case .left: mode = .tools(max(0, i - 1)); lastTool = max(0, i - 1)
            case .right: mode = .tools(min(2, i + 1)); lastTool = min(2, i + 1)
            case .down: mode = .anchor
            default: break
            }
        case .pills(let i):
            switch direction {
            case .left: mode = .pills(max(0, i - 1))
            case .right: mode = .pills(min(1, i + 1))
            case .up: mode = .anchor
            default: break
            }
        case .menu:
            menuMove(direction)
        }
        touch()
    }

    func select() {
        switch mode {
        case .hidden:
            engine.togglePlayPause()
            mode = .anchor
        case .anchor:
            engine.togglePlayPause()
        case .tools(let i):
            openMenu(tool: i)
        case .pills:
            break
        case .menu:
            menuSelect()
        }
        touch()
    }

    func playPause() {
        engine.togglePlayPause()
        if mode == .hidden { mode = .anchor }
        touch()
    }

    func menuButton() {
        if loadError != nil { finish(.failure); return }
        switch mode {
        case .hidden:
            finish(.cancel)
        case .anchor, .tools, .pills:
            mode = .hidden
        case .menu:
            popMenu()
        }
        touch()
    }

    /// Shows the bar for a moment, then hides it again while playing.
    func touch() {
        hideTask?.cancel()
        switch mode {
        case .anchor, .tools:
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.state == .playing, self.mode == .anchor || self.isToolsMode { self.mode = .hidden }
            }
        case .pills:
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if case .pills = self.mode { self.mode = .hidden }
            }
        default:
            break
        }
    }

    private var isToolsMode: Bool {
        if case .tools = mode { return true }
        return false
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
        mode = .anchor

        seekTask?.cancel()
        seekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self, let t = self.scrubTime else { return }
            await self.engine.seek(to: t)
            self.scrubTime = nil
        }
    }

    // MARK: - Menus

    func openMenu(tool i: Int) {
        lastTool = i
        let kind: MenuKind = i == 0 ? .subtitles : (i == 1 ? .audio : .playback)
        menuStack = [kind]
        mode = .menu
        menuFocus = defaultFocus(for: kind)
    }

    var currentMenu: MenuKind? { menuStack.last }

    func pushMenu(_ kind: MenuKind) {
        menuStack.append(kind)
        menuFocus = defaultFocus(for: kind)
    }

    func popMenu() {
        if !menuStack.isEmpty { menuStack.removeLast() }
        if let top = menuStack.last {
            menuFocus = defaultFocus(for: top)
        } else {
            menuFocus = nil
            mode = .tools(lastTool)
        }
    }

    func closeMenus() {
        menuStack = []
        menuFocus = nil
        mode = .anchor
    }

    private func defaultFocus(for kind: MenuKind) -> String? {
        let focusable = rows(for: kind).filter(\.focusable)
        if kind == .subtitleLanguage { return (focusable.first { $0.selected } ?? focusable.first)?.id }
        return focusable.first?.id
    }

    private func menuMove(_ direction: MoveCommandDirection) {
        guard let kind = currentMenu else { return }
        let focusable = rows(for: kind).filter(\.focusable)
        guard !focusable.isEmpty else { return }
        let index = focusable.firstIndex { $0.id == menuFocus } ?? 0
        switch direction {
        case .up: menuFocus = focusable[max(0, index - 1)].id
        case .down: menuFocus = focusable[min(focusable.count - 1, index + 1)].id
        case .left: focusable[index].adjust?(-1); objectWillChange.send()
        case .right: focusable[index].adjust?(1); objectWillChange.send()
        @unknown default: break
        }
    }

    private func menuSelect() {
        guard let kind = currentMenu else { return }
        let focusable = rows(for: kind).filter(\.focusable)
        guard let row = focusable.first(where: { $0.id == menuFocus }) ?? focusable.first else { return }
        row.select?()
        objectWillChange.send()
    }

    // MARK: - Track and playback actions

    func selectAudio(_ track: TrackInfo) { engine.selectAudioTrack(index: track.id) }

    func selectSubtitle(_ track: TrackInfo) {
        lastSubtitleID = track.id
        engine.selectSubtitleTrack(index: track.id)
    }

    func subtitlesOff() { engine.clearSubtitle() }

    func subtitlesOn() {
        let id = lastSubtitleID ?? subtitleTracks.first(where: { !$0.isForced })?.id ?? subtitleTracks.first?.id
        if let id, let track = subtitleTracks.first(where: { $0.id == id }) { selectSubtitle(track) }
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = (seconds * 10).rounded() / 10
        engine.setSoftwareSubtitleDelay(subtitleDelay)
    }

    func setAudioDelay(ms: Int) {
        audioDelayMs = max(-1000, min(1000, ms))
        engine.setAudioDelay(Double(audioDelayMs) / 1000.0)
    }

    func setSpeed(_ rate: Float) {
        speed = rate
        engine.setRate(rate)
    }

    /// Re-apply the current Settings to the playing session (route changes included).
    func reloadWithCurrentSettings() {
        let snapshot = settings
        showToast("Applying settings…")
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.engine.reloadAtCurrentPosition { options in
                    snapshot.apply(to: &options)
                }
                self.showToast("Settings applied")
            } catch {
                self.loadError = "Reload failed: \(error)"
            }
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self?.toast = nil }
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
        menuStack = []
        menuFocus = nil
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
}
