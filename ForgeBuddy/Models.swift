import Foundation
import SwiftUI

struct BuddyFolder: Identifiable, Codable, Hashable {
    var path: String
    var name: String
    var noteCount: Int

    var id: String { path }

    init(path: String, name: String, noteCount: Int = 0) {
        self.path = path
        self.name = name
        self.noteCount = noteCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        noteCount = try container.decodeIfPresent(Int.self, forKey: .noteCount) ?? 0
    }
}

struct BuddyNote: Identifiable, Codable, Hashable {
    var path: String
    var folderPath: String
    var title: String
    var transcript: String
    var recordedAt: Date?
    var durationSeconds: Double?
    var audioPath: String?

    var id: String { path }

    init(
        path: String,
        folderPath: String,
        title: String,
        transcript: String,
        recordedAt: Date? = nil,
        durationSeconds: Double? = nil,
        audioPath: String? = nil
    ) {
        self.path = path
        self.folderPath = folderPath
        self.title = title
        self.transcript = transcript
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.audioPath = audioPath
    }

    enum CodingKeys: String, CodingKey {
        case path
        case folderPath
        case title
        case transcript
        case recordedAt
        case durationSeconds
        case audioPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        if let rawDate = try container.decodeIfPresent(String.self, forKey: .recordedAt) {
            recordedAt = ISO8601DateFormatter.forge.date(from: rawDate)
        } else {
            recordedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(title, forKey: .title)
        try container.encode(transcript, forKey: .transcript)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(audioPath, forKey: .audioPath)
        if let recordedAt {
            try container.encode(ISO8601DateFormatter.forge.string(from: recordedAt), forKey: .recordedAt)
        }
    }
}

struct PairingInfo: Codable, Equatable {
    var baseURL: URL
    var altURLs: [URL]
    var token: String
    var desktop: String
    var pairedAt: Date

    var endpoints: [URL] {
        [baseURL] + altURLs.filter { $0 != baseURL }
    }

    static func parse(_ url: URL) throws -> PairingInfo {
        guard url.scheme == "forge-buddy" else {
            throw ForgeBuddyError.message("That QR code is not for Forge Buddy.")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ForgeBuddyError.message("The pairing link is malformed.")
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        guard let base = query["baseURL"], let baseURL = URL(string: base), let token = query["token"] else {
            throw ForgeBuddyError.message("The pairing link is missing connection details.")
        }

        let altURLs = (query["altURLs"] ?? "")
            .split(separator: ",")
            .compactMap { URL(string: String($0)) }

        return PairingInfo(
            baseURL: baseURL,
            altURLs: altURLs,
            token: token,
            desktop: query["desktop"] ?? "Forge for Mac",
            pairedAt: Date()
        )
    }
}

enum ForgeBuddyError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case light
    case system
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var title: String {
        switch self {
        case .light: return "Light"
        case .system: return "System"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "sun.max"
        case .system: return "desktopcomputer"
        case .dark: return "moon"
        }
    }
}

enum AppScreen: Equatable {
    case welcome
    case scan
    case connecting
    case paired
    case home
    case folder(String)
    case recording(String)
    case detail(String)
    case settings
}

enum BuddySheet: Identifiable, Equatable {
    case newFolder
    case moveNote(String)
    case folderOptions(String)
    case renameFolder(String)
    case deleteFolder(String)

    var id: String {
        switch self {
        case .newFolder:
            return "new-folder"
        case .moveNote(let path):
            return "move-\(path)"
        case .folderOptions(let path):
            return "folder-options-\(path)"
        case .renameFolder(let path):
            return "rename-\(path)"
        case .deleteFolder(let path):
            return "delete-\(path)"
        }
    }
}

struct RecordingResult {
    var transcript: String
    var audioURL: URL
    var durationSeconds: Double
}

extension ISO8601DateFormatter {
    static let forge: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
