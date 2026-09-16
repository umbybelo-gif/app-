import Foundation

// MARK: - Clip

/// Una singola registrazione. Il file vive in Documents/Media/<fileName>.
struct Clip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var createdAt: Date = Date()
    var duration: Double = 0
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 0
    var codec: String = ""
    var colorMode: String = ""
    var stabilization: String = ""
    var lens: String = ""
    var fileSize: Int64 = 0
    var take: Int = 1
    /// Ciak buono: la ripresa che userai nel montaggio.
    var isSelect: Bool = false
    var note: String = ""
    /// Vero per i video aggiunti da Foto o da File invece che girati nell'app.
    var isImported: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, fileName, createdAt, duration, width, height, fps
        case codec, colorMode, stabilization, lens, fileSize, take, isSelect, note, isImported
    }

    var resolutionLabel: String {
        guard width > 0, height > 0 else { return "—" }
        let long = max(width, height), short = min(width, height)
        switch (long, short) {
        case (3840, 2160): return "4K"
        case (1920, 1080): return "1080p"
        case (1280, 720): return "720p"
        default: return "\(long)×\(short)"
        }
    }

    var originLabel: String { isImported ? "Importato" : "Girato con Ciak" }

    var durationLabel: String { Formatters.duration(duration) }
    var sizeLabel: String { Formatters.bytes(fileSize) }

    /// Riassunto tecnico da mostrare sotto la clip.
    var technicalSummary: String {
        var parts: [String] = [resolutionLabel]
        if fps > 0 { parts.append("\(Int(fps.rounded())) fps") }
        if !codec.isEmpty { parts.append(codec) }
        if !colorMode.isEmpty && colorMode != "SDR" { parts.append(colorMode) }
        return parts.joined(separator: " · ")
    }
}

extension Clip {
    /// Decodifica tollerante: un archivio scritto da una versione precedente
    /// dell'app resta leggibile anche quando si aggiungono nuovi campi.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decode(String.self, forKey: .fileName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? 0
        codec = try c.decodeIfPresent(String.self, forKey: .codec) ?? ""
        colorMode = try c.decodeIfPresent(String.self, forKey: .colorMode) ?? ""
        stabilization = try c.decodeIfPresent(String.self, forKey: .stabilization) ?? ""
        lens = try c.decodeIfPresent(String.self, forKey: .lens) ?? ""
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        take = try c.decodeIfPresent(Int.self, forKey: .take) ?? 1
        isSelect = try c.decodeIfPresent(Bool.self, forKey: .isSelect) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        isImported = try c.decodeIfPresent(Bool.self, forKey: .isImported) ?? false
    }
}

// MARK: - Sketch

/// Uno sketch: la singola idea / scena dentro un progetto.
struct Sketch: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var script: String = ""
    var createdAt: Date = Date()
    var isDone: Bool = false
    var clips: [Clip] = []

    var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
    var selectsCount: Int { clips.filter(\.isSelect).count }
    var nextTake: Int { (clips.map(\.take).max() ?? 0) + 1 }
}

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var notes: String = ""
    var createdAt: Date = Date()
    var colorIndex: Int = 0
    var isArchived: Bool = false
    var sketches: [Sketch] = []

    var clipCount: Int { sketches.reduce(0) { $0 + $1.clips.count } }
    var totalDuration: Double { sketches.reduce(0) { $0 + $1.totalDuration } }
}

// MARK: - Riferimento alla destinazione di registrazione

struct RecordingTarget: Hashable {
    var projectID: UUID
    var sketchID: UUID
}

// MARK: - Formatters

enum Formatters {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00.0" }
        let total = Int(seconds)
        let m = total / 60, s = total % 60
        let tenths = Int((seconds - Double(total)) * 10)
        return String(format: "%02d:%02d.%d", m, s, tenths)
    }

    static func bytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: count)
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}

// MARK: - Nomi file sicuri

extension String {
    /// Rende la stringa utilizzabile come nome di file/cartella.
    var fileSafe: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trimmed.isEmpty ? "Senza-nome" : trimmed
        return String(result.prefix(60))
    }
}
