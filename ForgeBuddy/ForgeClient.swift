import Foundation
import UIKit

struct ForgeClient {
    let pairing: PairingInfo

    func snapshot() async throws -> ([BuddyFolder], [BuddyNote]) {
        let response: SnapshotResponse = try await send(path: "/api/buddy/snapshot")
        return (response.folders, response.notes)
    }

    func createFolder(name: String) async throws -> BuddyFolder {
        let body = try JSONEncoder().encode(["name": name])
        let response: FolderResponse = try await send(path: "/api/buddy/folders/create", method: "POST", body: body)
        return response.folder
    }

    func renameFolder(path: String, newName: String) async throws -> BuddyFolder {
        let body = try JSONEncoder().encode(FolderRequest(path: path, name: nil, newName: newName))
        let response: FolderResponse = try await send(path: "/api/buddy/folders/rename", method: "POST", body: body)
        return response.folder
    }

    func deleteFolder(path: String) async throws {
        let body = try JSONEncoder().encode(FolderRequest(path: path, name: nil, newName: nil))
        let _: EmptyResponse = try await send(path: "/api/buddy/folders/delete", method: "POST", body: body)
    }

    func createNote(
        folderPath: String,
        transcript: String,
        audioURL: URL?,
        durationSeconds: Double,
        recordedAt: Date = Date()
    ) async throws -> BuddyNote {
        let audioData = try audioURL.map { try Data(contentsOf: $0) }
        let deviceName = await MainActor.run { UIDevice.current.name }
        let request = NoteRequest(
            path: nil,
            folderPath: folderPath,
            transcript: transcript,
            title: Self.title(from: transcript),
            recordedAt: ISO8601DateFormatter.forge.string(from: recordedAt),
            durationSeconds: durationSeconds,
            deviceName: deviceName,
            audioBase64: audioData?.base64EncodedString(),
            audioFileName: audioURL?.lastPathComponent
        )
        let body = try JSONEncoder().encode(request)
        let response: NoteResponse = try await send(path: "/api/buddy/notes/create", method: "POST", body: body)
        return response.note
    }

    func updateNote(path: String, transcript: String) async throws -> BuddyNote {
        let body = try JSONEncoder().encode(NoteRequest(path: path, folderPath: nil, transcript: transcript))
        let response: NoteResponse = try await send(path: "/api/buddy/notes/update", method: "POST", body: body)
        return response.note
    }

    func moveNote(path: String, folderPath: String) async throws -> BuddyNote {
        let body = try JSONEncoder().encode(NoteRequest(path: path, folderPath: folderPath))
        let response: NoteResponse = try await send(path: "/api/buddy/notes/move", method: "POST", body: body)
        return response.note
    }

    func deleteNote(path: String) async throws {
        let body = try JSONEncoder().encode(NoteRequest(path: path))
        let _: EmptyResponse = try await send(path: "/api/buddy/notes/delete", method: "POST", body: body)
    }

    func audioURL(path audioPath: String) -> URL? {
        var components = URLComponents(
            url: pairing.baseURL.appendingPathComponent("api/buddy/audio"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "path", value: audioPath),
            URLQueryItem(name: "token", value: pairing.token)
        ]
        return components?.url
    }

    private func send<Response: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> Response {
        var lastError: Error?

        for endpoint in pairing.endpoints {
            do {
                let url = endpoint.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.timeoutInterval = 8
                request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let body {
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ForgeBuddyError.message("Forge did not return an HTTP response.")
                }
                guard 200..<300 ~= http.statusCode else {
                    let serverError = try? JSONDecoder().decode(ServerError.self, from: data)
                    throw ForgeBuddyError.message(serverError?.error ?? "Forge returned HTTP \(http.statusCode).")
                }
                return try JSONDecoder.forge.decode(Response.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ForgeBuddyError.message("Could not reach Forge on your Mac.")
    }

    private static func title(from transcript: String) -> String {
        let words = transcript
            .split(whereSeparator: \.isWhitespace)
            .prefix(7)
            .joined(separator: " ")
        return words.isEmpty ? "Voice Note" : words
    }
}

private struct SnapshotResponse: Decodable {
    var ok: Bool
    var folders: [BuddyFolder]
    var notes: [BuddyNote]
}

private struct FolderResponse: Decodable {
    var ok: Bool
    var folder: BuddyFolder
}

private struct NoteResponse: Decodable {
    var ok: Bool
    var note: BuddyNote
}

private struct EmptyResponse: Decodable {
    var ok: Bool
}

private struct ServerError: Decodable {
    var ok: Bool?
    var error: String
}

private struct FolderRequest: Encodable {
    var path: String?
    var name: String?
    var newName: String?
}

private struct NoteRequest: Encodable {
    var path: String?
    var folderPath: String?
    var transcript: String?
    var title: String?
    var recordedAt: String?
    var durationSeconds: Double?
    var deviceName: String?
    var audioBase64: String?
    var audioFileName: String?

    init(
        path: String? = nil,
        folderPath: String? = nil,
        transcript: String? = nil,
        title: String? = nil,
        recordedAt: String? = nil,
        durationSeconds: Double? = nil,
        deviceName: String? = nil,
        audioBase64: String? = nil,
        audioFileName: String? = nil
    ) {
        self.path = path
        self.folderPath = folderPath
        self.transcript = transcript
        self.title = title
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.deviceName = deviceName
        self.audioBase64 = audioBase64
        self.audioFileName = audioFileName
    }
}

extension JSONDecoder {
    static let forge: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
