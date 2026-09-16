import AVFoundation
import Foundation

enum CodecPreference: String, Codable, CaseIterable, Identifiable {
    case hevc, h264, proRes
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hevc: return "HEVC"
        case .h264: return "H.264"
        case .proRes: return "ProRes"
        }
    }

    var detail: String {
        switch self {
        case .hevc: return "Massima qualità per file contenuti. Consigliato."
        case .h264: return "Massima compatibilità con software vecchi. File più grandi."
        case .proRes: return "Qualità da montaggio, pochissima compressione. File enormi."
        }
    }
}

enum ColorPreference: String, Codable, CaseIterable, Identifiable {
    case sdr, hdr, appleLog
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sdr: return "SDR"
        case .hdr: return "HDR (HLG)"
        case .appleLog: return "Apple Log"
        }
    }

    var detail: String {
        switch self {
        case .sdr: return "Colore standard: pronto da pubblicare senza ritocchi."
        case .hdr: return "10 bit ad alta gamma dinamica. Ottimo per social moderni."
        case .appleLog: return "Profilo piatto per color grading. Solo iPhone 15 Pro e successivi."
        }
    }
}

enum StabilizationPreference: String, Codable, CaseIterable, Identifiable {
    case maximum, cinematic, standard, off
    var id: String { rawValue }

    var label: String {
        switch self {
        case .maximum: return "Massima"
        case .cinematic: return "Cinematica"
        case .standard: return "Standard"
        case .off: return "Disattivata"
        }
    }

    var detail: String {
        switch self {
        case .maximum: return "La più forte disponibile. Ritaglia un po' l'inquadratura."
        case .cinematic: return "Movimenti fluidi con ritaglio contenuto."
        case .standard: return "Correzione leggera, nessun ritaglio percepibile."
        case .off: return "Nessuna stabilizzazione (per riprese su treppiede o gimbal)."
        }
    }

    /// Ordine di preferenza: si applica la prima modalità supportata dal formato attivo.
    var candidates: [AVCaptureVideoStabilizationMode] {
        switch self {
        case .maximum:
            var modes: [AVCaptureVideoStabilizationMode] = []
            if #available(iOS 18.0, *) { modes.append(.cinematicExtendedEnhanced) }
            modes.append(contentsOf: [.cinematicExtended, .cinematic, .standard])
            return modes
        case .cinematic:
            return [.cinematicExtended, .cinematic, .standard]
        case .standard:
            return [.standard]
        case .off:
            return [.off]
        }
    }
}

struct CaptureSettings: Codable, Equatable {
    var width: Int = 3840
    var height: Int = 2160
    var fps: Double = 30
    var codec: CodecPreference = .hevc
    var color: ColorPreference = .sdr
    var stabilization: StabilizationPreference = .maximum
    var stereoAudio: Bool = true
    var windNoiseRemoval: Bool = true
    var mirrorFrontCamera: Bool = false
    var showGrid: Bool = true
    var showLevel: Bool = false
    var showZebra: Bool = false
    var keepScreenAwake: Bool = true

    static let storageKey = "capture.settings.v1"

    static func load() -> CaptureSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(CaptureSettings.self, from: data)
        else { return CaptureSettings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    var resolutionLabel: String {
        switch (max(width, height), min(width, height)) {
        case (3840, 2160): return "4K"
        case (1920, 1080): return "1080p"
        case (1280, 720): return "720p"
        default: return "\(max(width, height))p"
        }
    }
}

/// Una risoluzione selezionabile. Tipo nostro invece di estendere `CMVideoDimensions`,
/// che è un tipo importato dal C e non va conformato a protocolli Swift.
struct Resolution: Hashable, Identifiable {
    let width: Int
    let height: Int

    var id: String { "\(width)x\(height)" }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ dimensions: CMVideoDimensions) {
        self.init(width: Int(dimensions.width), height: Int(dimensions.height))
    }

    var pixels: Int { width * height }

    var label: String {
        let long = max(width, height), short = min(width, height)
        switch (long, short) {
        case (3840, 2160): return "4K UHD (3840×2160)"
        case (1920, 1080): return "Full HD (1920×1080)"
        case (1280, 720): return "HD (1280×720)"
        default: return "\(long)×\(short)"
        }
    }
}

// MARK: - Utility sui formati

extension AVCaptureDevice.Format {
    var dimensions: CMVideoDimensions { CMVideoFormatDescriptionGetDimensions(formatDescription) }
    var pixelSubType: FourCharCode { CMFormatDescriptionGetMediaSubType(formatDescription) }

    /// I formati ProRes espongono un sotto-tipo 'x422'.
    var isProResFormat: Bool { pixelSubType == FourCharCode.from("x422") }
    /// I formati a 10 bit ('x420') abilitano HDR e Apple Log.
    var isTenBit: Bool { pixelSubType == FourCharCode.from("x420") || isProResFormat }

    var maxFrameRate: Double {
        videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
    }

    func supports(fps: Double) -> Bool {
        videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fps + 0.01 && fps <= $0.maxFrameRate + 0.01 }
    }

    var supportsAppleLog: Bool {
        if #available(iOS 17.0, *) { return supportedColorSpaces.contains(.appleLog) }
        return false
    }
}

extension FourCharCode {
    static func from(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for byte in string.utf8.prefix(4) { result = (result << 8) + FourCharCode(byte) }
        return result
    }
}

extension AVCaptureVideoStabilizationMode {
    var label: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .cinematic: return "Cinematica"
        case .cinematicExtended: return "Cinematica estesa"
        case .auto: return "Auto"
        default:
            if #available(iOS 18.0, *), self == .cinematicExtendedEnhanced { return "Cinematica potenziata" }
            return "Sconosciuta"
        }
    }
}
