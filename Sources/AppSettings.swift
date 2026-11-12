import Foundation
import SwiftUI
import HostDeps

// MARK: - Choices (each maps onto a real AetherEngine LoadOptions field)

/// `LoadOptions.dolbyVisionHandling`
enum DVHandlingChoice: String, Codable, CaseIterable, Identifiable {
    case automatic, baseLayerOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Dolby Vision when possible"
        case .baseLayerOnly: "HDR10 base layer only (ignore Dolby Vision)"
        }
    }
}

/// How Profile 7 FEL (Blu-ray style dual-layer Dolby Vision) is handled.
/// Maps onto `foldsDolbyVisionFEL`, `preferDualLayerDolbyVision` and `dualLayerRoute`.
enum FELChoice: String, Codable, CaseIterable, Identifiable {
    case off, curves, dualLayerSoftware, dualLayerAVPlayer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off: plain Profile 8.1 conversion"
        case .curves: "Enhanced conversion (FEL curves folded into 8.1)"
        case .dualLayerSoftware: "Full dual-layer FEL (GPU, software host)"
        case .dualLayerAVPlayer: "Full dual-layer FEL (AVPlayer output)"
        }
    }
    var detail: String {
        switch self {
        case .off:
            "Fastest start and seek. FEL detail is dropped."
        case .curves:
            "Engine default. Keeps most of the FEL effect on the normal Dolby Vision route."
        case .dualLayerSoftware:
            "Decodes both layers. Needs a UHD 30 fps title or smaller. Dolby Atmos (E-AC-3 JOC) plays as its 5.1/7.1 core on this route."
        case .dualLayerAVPlayer:
            "Keeps AVPlayer's audio, so Atmos objects stay. The engine says it has not been run on tvOS yet."
        }
    }
}

/// `LoadOptions.objectAudioRendering`: TrueHD Atmos and DTS:X delivery.
enum AtmosChoice: String, Codable, CaseIterable, Identifiable {
    case off, l512, l514, l712, l714, l916
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off: plain 7.1 channel decode"
        case .l512: "Render to 5.1.2"
        case .l514: "Render to 5.1.4"
        case .l712: "Render to 7.1.2"
        case .l714: "Render to 7.1.4"
        case .l916: "Render to 9.1.6"
        }
    }
    var rendering: ObjectAudioRendering {
        switch self {
        case .off: return .off
        case .l512: return .render(.l512)
        case .l514: return .render(.l514)
        case .l712: return .render(.l712)
        case .l714: return .render(.l714)
        case .l916: return .render(.l916)
        }
    }
}

/// `LoadOptions.audioBridgeMode`
enum BridgeChoice: String, Codable, CaseIterable, Identifiable {
    case surroundCompat, lossless
    var id: String { rawValue }
    var label: String {
        switch self {
        case .surroundCompat: "Compatible surround (E-AC-3, lossy)"
        case .lossless: "Lossless multichannel (FLAC up to 7.1)"
        }
    }
    var mode: AudioBridgeMode {
        switch self {
        case .surroundCompat: return .surroundCompat
        case .lossless: return .lossless
        }
    }
}

/// Used for both `preferredAudioLanguages` and `preferredSubtitleLanguages` (ISO 639-1).
enum LangChoice: String, Codable, CaseIterable, Identifiable {
    case none = "", en, ru, lv, de, fr, es, it, uk, pl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Default / none"
        case .en: "English"
        case .ru: "Russian"
        case .lv: "Latvian"
        case .de: "German"
        case .fr: "French"
        case .es: "Spanish"
        case .it: "Italian"
        case .uk: "Ukrainian"
        case .pl: "Polish"
        }
    }
    var codes: [String] { rawValue.isEmpty ? [] : [rawValue] }
}

enum SubtitleSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .small: 34
        case .medium: 44
        case .large: 56
        }
    }
}

/// Where "Menu" takes you back to when playback ends or is cancelled.
enum ReturnChoice: String, Codable, CaseIterable, Identifiable {
    case lampa, luxo, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lampa: "Lampa  (lampa://)"
        case .luxo: "Luxo  (luxo://)"
        case .none: "Stay in this app"
        }
    }
}

// MARK: - Stored values

struct SettingValues: Codable, Equatable {
    // Video
    var dvHandling: DVHandlingChoice = .automatic
    var fel: FELChoice = .curves
    var upscale = false
    var upscaleLineArt = false
    // Audio
    var atmos: AtmosChoice = .l512
    var bridge: BridgeChoice = .surroundCompat
    var audioDelayMs = 0
    var audioLanguage: LangChoice = .none
    var subtitleLanguage: LangChoice = .none
    // Player
    var skipSeconds = 10
    var resume = true
    var subtitleSize: SubtitleSize = .medium
    var showDebugInfo = false
    var returnTo: ReturnChoice = .lampa

    init() {}

    // Tolerant decoding: a field added in a later version must not wipe the stored settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let d = SettingValues()
        dvHandling = get(.dvHandling, d.dvHandling)
        fel = get(.fel, d.fel)
        upscale = get(.upscale, d.upscale)
        upscaleLineArt = get(.upscaleLineArt, d.upscaleLineArt)
        atmos = get(.atmos, d.atmos)
        bridge = get(.bridge, d.bridge)
        audioDelayMs = get(.audioDelayMs, d.audioDelayMs)
        audioLanguage = get(.audioLanguage, d.audioLanguage)
        subtitleLanguage = get(.subtitleLanguage, d.subtitleLanguage)
        skipSeconds = get(.skipSeconds, d.skipSeconds)
        resume = get(.resume, d.resume)
        subtitleSize = get(.subtitleSize, d.subtitleSize)
        showDebugInfo = get(.showDebugInfo, d.showDebugInfo)
        returnTo = get(.returnTo, d.returnTo)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let storageKey = "settings.v1"

    @Published var v: SettingValues {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SettingValues.self, from: data) {
            v = decoded
        } else {
            v = SettingValues()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(v) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Writes every setting that maps onto the engine into a `LoadOptions`.
    /// Used for a fresh `load` and for `reloadAtCurrentPosition(applying:)`.
    func apply(to o: inout LoadOptions) {
        o.dolbyVisionHandling = v.dvHandling == .automatic ? .automatic : .baseLayerOnly

        switch v.fel {
        case .off:
            o.preferDualLayerDolbyVision = false
            o.foldsDolbyVisionFEL = false
        case .curves:
            o.preferDualLayerDolbyVision = false
            o.foldsDolbyVisionFEL = true
        case .dualLayerSoftware:
            o.preferDualLayerDolbyVision = true
            o.dualLayerRoute = .softwareHost
        case .dualLayerAVPlayer:
            o.preferDualLayerDolbyVision = true
            o.dualLayerRoute = .avPlayerOutput
        }

        o.upscalesLowResolutionVideo = v.upscale
        o.upscaleScaler = v.upscaleLineArt ? .lineArt : .automatic

        o.objectAudioRendering = v.atmos.rendering
        o.audioBridgeMode = v.bridge.mode
        o.audioDelaySeconds = Double(v.audioDelayMs) / 1000.0
        o.preferredAudioLanguages = v.audioLanguage.codes
        o.preferredSubtitleLanguages = v.subtitleLanguage.codes
    }

    var returnScheme: String? {
        switch v.returnTo {
        case .lampa: return "lampa"
        case .luxo: return "luxo"
        case .none: return nil
        }
    }

    // MARK: Which optional engine components this build actually contains

    var hasTrueHD: Bool { AetherEngine.OptionalComponent.trueHDObjectAudio.isBuiltIn }
    var hasDTSX: Bool { AetherEngine.OptionalComponent.dtsxObjectAudio.isBuiltIn }
    var hasDualLayer: Bool { AetherEngine.OptionalComponent.dualLayerDolbyVision.isBuiltIn }
    var hasFelCurves: Bool { AetherEngine.OptionalComponent.dolbyVisionFelCurves.isBuiltIn }
}
