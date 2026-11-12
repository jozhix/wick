import SwiftUI
import HostDeps

/// Shown whenever nothing is playing (and it is what you see if you open the app directly).
/// Settings are stored on the device and read at the start of each playback.
struct SettingsScreen: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var settings: AppSettings

    init(model: PlayerModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Waiting for Lampa. In Lampa set the Apple TV torrent player to \"SenPlayer\"; its stream links open here.")
                        .font(.callout)
                    if let message = model.message {
                        Text(message).font(.callout).foregroundStyle(.orange)
                    }
                }

                Section("Video") {
                    Picker("Dolby Vision", selection: $settings.v.dvHandling) {
                        ForEach(DVHandlingChoice.allCases) { Text($0.label).tag($0) }
                    }

                    Picker("Dolby Vision FEL (Profile 7)", selection: $settings.v.fel) {
                        ForEach(FELChoice.allCases) { Text($0.label).tag($0) }
                    }
                    note(settings.v.fel.detail)
                    if settings.v.fel == .curves && !settings.hasFelCurves {
                        warn("This build was made without the FEL curves component, so this setting does nothing.")
                    }
                    if (settings.v.fel == .dualLayerSoftware || settings.v.fel == .dualLayerAVPlayer) && !settings.hasDualLayer {
                        warn("This build was made without the dual-layer component, so this setting does nothing.")
                    }

                    Toggle("Upscale low-resolution video", isOn: $settings.v.upscale)
                    if settings.v.upscale {
                        Toggle("Line-art upscaler (animation)", isOn: $settings.v.upscaleLineArt)
                    }
                }

                Section("Audio") {
                    Picker("TrueHD / DTS:X Atmos", selection: $settings.v.atmos) {
                        ForEach(AtmosChoice.allCases) { Text($0.label).tag($0) }
                    }
                    note("Renders object audio into a fixed speaker layout. Pick the layout your receiver actually drives.")
                    if settings.v.atmos != .off && !settings.hasTrueHD {
                        warn("This build was made without the TrueHD component, so TrueHD stays a plain channel decode.")
                    }
                    if settings.v.atmos != .off && !settings.hasDTSX {
                        warn("This build was made without the DTS:X component.")
                    }

                    Picker("Bridge for TrueHD / DTS / Opus", selection: $settings.v.bridge) {
                        ForEach(BridgeChoice.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Audio delay", selection: $settings.v.audioDelayMs) {
                        ForEach(Array(stride(from: -300, through: 300, by: 50)), id: \.self) { ms in
                            Text(ms == 0 ? "None" : "\(ms > 0 ? "+" : "")\(ms) ms").tag(ms)
                        }
                    }
                    Picker("Preferred audio language", selection: $settings.v.audioLanguage) {
                        ForEach(LangChoice.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Subtitles") {
                    Picker("Preferred subtitle language", selection: $settings.v.subtitleLanguage) {
                        ForEach(LangChoice.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Size", selection: $settings.v.subtitleSize) {
                        ForEach(SubtitleSize.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Player") {
                    Picker("Skip step", selection: $settings.v.skipSeconds) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Toggle("Resume where I stopped", isOn: $settings.v.resume)
                    Toggle("Show technical info on the transport bar", isOn: $settings.v.showDebugInfo)
                    Picker("When playback ends, go back to", selection: $settings.v.returnTo) {
                        ForEach(ReturnChoice.allCases) { Text($0.label).tag($0) }
                    }
                    note("Settings apply to the next playback. During playback use ▲ ▼ then \"Reload with current Settings\".")
                }

                Section("Lampa players this app answers as") {
                    ForEach(RegisteredPlayers.current, id: \.scheme) { entry in
                        LabeledContent(entry.lampaName, value: entry.scheme + "://")
                    }
                    note("Choose one of these names as the Apple TV player in Lampa. The list is fixed when the app is installed; change it with tools/set_schemes.py and reinstall. \"Inner\" is Lampa's own web player and has no link, so it cannot be claimed.")
                }

                Section("About") {
                    LabeledContent("Dual-layer Dolby Vision", value: settings.hasDualLayer ? "in this build" : "not in this build")
                    LabeledContent("FEL curves", value: settings.hasFelCurves ? "in this build" : "not in this build")
                    LabeledContent("TrueHD Atmos", value: settings.hasTrueHD ? "in this build" : "not in this build")
                    LabeledContent("DTS:X", value: settings.hasDTSX ? "in this build" : "not in this build")
                }
            }
            .navigationTitle("Aether Player")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }

    private func warn(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.orange)
    }
}
