import SwiftUI

enum FootageType: String, CaseIterable, Identifiable, Codable {
    case talk, aroll, vo, offscreen, broll, scenery, photo
    var id: String { rawValue }

    var code: String {
        switch self {
        case .talk: return "TALK"
        case .aroll: return "AROLL"
        case .vo: return "VO"
        case .offscreen: return "OFFSCREEN"
        case .broll: return "BROLL"
        case .scenery: return "SCENERY"
        case .photo: return "PHOTO"
        }
    }
    var label: String {
        switch self {
        case .talk: return "Talking head"
        case .aroll: return "A-roll"
        case .vo: return "Voice over"
        case .offscreen: return "Off-screen dialogue"
        case .broll: return "B-roll"
        case .scenery: return "Scenery"
        case .photo: return "Photo"
        }
    }
    var folder: String {
        switch self {
        case .talk: return "Talking-Head"
        case .aroll: return "A-Roll"
        case .vo: return "Voice-Over"
        case .offscreen: return "Off-Screen-Dialogue"
        case .broll: return "B-Roll"
        case .scenery: return "Scenery"
        case .photo: return "Photos"
        }
    }
    var color: Color {
        switch self {
        case .talk: return Color(hex: "1E3A5F")
        case .aroll: return Color(hex: "2F6B6B")
        case .vo: return Color(hex: "8A5A1F")
        case .offscreen: return Color(hex: "6B4A8E")
        case .broll: return Color(hex: "3D6E9E")
        case .scenery: return Color(hex: "5B7A57")
        case .photo: return Color(hex: "88074D")
        }
    }
    static var videoTypes: [FootageType] { [.talk, .aroll, .vo, .offscreen, .broll, .scenery] }
    static func from(code: String) -> FootageType? { allCases.first { $0.code == code } }
}

struct Analysis {
    var speechShare = 0.0
    var longestRun = 0.0
    var faceShare = 0.0
    var faceSize = 0.0
    var personShare = 0.0
    var cuts = 0
    var narrated = false
}

struct WrangleItem: Identifiable {
    let id = UUID()
    let url: URL
    let sourceURL: URL
    let sourceLabel: String
    let isVideo: Bool
    var created: Date
    var dateFromFile: Bool
    var duration: Double = 0
    var fps: Double = 0
    var pixelSize: CGSize = .zero
    var bytes: Int64 = 0
    var analysis = Analysis()
    var type: FootageType = .broll
    var confident = true
    var accepted = false
    var duplicateOf: String? = nil
    var camera = "Phone"
    var newName = ""
    var destination: URL? = nil
    /// Where the file was taken, if it has GPS.
    var gps: GPS? = nil
    /// City name from the GPS, e.g. "Paris". Nil when there's no GPS or no connection.
    var place: String? = nil
    /// A location the user set for this file by hand. Wins over GPS and the default.
    var manualLocation: String? = nil
    /// The location actually used in the name: hand-set, then GPS place, then the run's location.
    var location = ""

    var needsInput: Bool { duplicateOf == nil && !confident && !accepted }
    var ext: String {
        let e = url.pathExtension.lowercased()
        return e == "jpeg" ? "jpg" : e
    }
    var createdText: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy · HH:mm"
        return f.string(from: created)
    }
}

struct LibraryFile: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let type: FootageType?
    let date: String
    let location: String
    let standardized: Bool
    let bytes: Int64
    let folder: String
    let isOffline: Bool
    let isVideo: Bool
    /// The words of the clip's .srt transcript, when it has one.
    var transcript: String? = nil
    /// The file's name before Lasso renamed it, from the rename log.
    var previousName: String? = nil
    /// Names of the people Lasso recognised in this file (kept only inside Lasso).
    var people: [String] = []
}

enum RenameMode: String, CaseIterable, Identifiable {
    case copy, move, inPlace
    var id: String { rawValue }
    var label: String {
        switch self {
        case .copy: return "Copy to the library: originals stay where they are located."
        case .move: return "Move to the library: originals moved to the library."
        case .inPlace: return "Rename in place: files stay in same folder, new name only."
        }
    }
    /// Copy and Move both put the renamed file in the library.
    var usesLibrary: Bool { self != .inPlace }
}

enum ViewSize: String, CaseIterable, Identifiable {
    case large = "Large", medium = "Medium", small = "Small", list = "List"
    var id: String { rawValue }
}

enum NameToken: String, CaseIterable, Identifiable, Codable {
    case date, location, type, seq, time, camera, project
    var id: String { rawValue }
    var label: String {
        switch self {
        case .date: return "Date"
        case .location: return "Location"
        case .type: return "TYPE"
        case .seq: return "###"
        case .time: return "Time"
        case .camera: return "Camera"
        case .project: return "Project"
        }
    }
    static let defaultOrder: [NameToken] = [.date, .location, .type, .seq]
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "Photos & videos", video = "Videos", photo = "Photos"
    var id: String { rawValue }
}
