import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: AppScreen = .welcome
    @Published var sheet: BuddySheet?
    @Published var folders: [BuddyFolder] = []
    @Published var notes: [BuddyNote] = []
    @Published var pairing: PairingInfo?
    @Published var appearance: AppearanceMode = .system
    @Published var isConnected = false
    @Published var statusText = "Offline"
    @Published var errorMessage: String?

    let recorder = RecorderService()

    private let store = BuddyStore()

    init() {
        let state = store.load()
        folders = state.folders
        notes = state.notes
        pairing = state.pairing
        appearance = state.appearance
        screen = state.hasCompletedWelcome || state.pairing != nil ? .home : .welcome
        if folders.isEmpty {
            folders = [
                BuddyFolder(path: "Inbox", name: "Inbox", noteCount: 0),
                BuddyFolder(path: "Meetings", name: "Meetings", noteCount: 0),
                BuddyFolder(path: "Ideas", name: "Ideas", noteCount: 0)
            ]
        }
    }

    var client: ForgeClient? {
        pairing.map(ForgeClient.init(pairing:))
    }

    func completeWelcome() {
        store.hasCompletedWelcome = true
        save()
        screen = .home
    }

    func beginPairing() {
        screen = .scan
    }

    func handlePairingURL(_ url: URL) {
        Task {
            do {
                let info = try PairingInfo.parse(url)
                screen = .connecting
                pairing = info
                save()
                try await Task.sleep(for: .milliseconds(650))
                await refresh()
                screen = .paired
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func finishPairedScreen() {
        store.hasCompletedWelcome = true
        save()
        screen = .home
    }

    func refresh() async {
        guard let client else {
            isConnected = false
            statusText = "Not paired"
            return
        }

        do {
            statusText = "Syncing"
            let snapshot = try await client.snapshot()
            folders = snapshot.0
            notes = snapshot.1
            ensureFolderSelection()
            isConnected = true
            statusText = "Connected"
            errorMessage = nil
            save()
        } catch {
            isConnected = false
            statusText = "Offline"
            errorMessage = error.localizedDescription
        }
    }

    func notes(in folderPath: String) -> [BuddyNote] {
        notes
            .filter { $0.folderPath == folderPath }
            .sorted {
                ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast)
            }
    }

    func folder(path: String) -> BuddyFolder? {
        folders.first { $0.path == path }
    }

    func note(path: String) -> BuddyNote? {
        notes.first { $0.path == path }
    }

    func audioURL(for note: BuddyNote) -> URL? {
        guard let audioPath = note.audioPath else { return nil }
        return client?.audioURL(path: audioPath)
    }

    func createFolder(named rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            if let client {
                let folder = try await client.createFolder(name: name)
                upsert(folder: folder)
                await refresh()
            } else {
                let path = uniqueLocalFolderPath(name)
                folders.append(BuddyFolder(path: path, name: name, noteCount: 0))
                save()
            }
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameFolder(path: String, to rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            if let client {
                let folder = try await client.renameFolder(path: path, newName: name)
                upsert(folder: folder)
                await refresh()
                screen = .folder(folder.path)
            } else if let index = folders.firstIndex(where: { $0.path == path }) {
                let parent = Self.parentPath(path)
                let nextPath = parent == "." ? name : "\(parent)/\(name)"
                folders[index].path = nextPath
                folders[index].name = name
                notes = notes.map { note in
                    guard note.folderPath == path else { return note }
                    var copy = note
                    copy.folderPath = nextPath
                    copy.path = note.path.replacingOccurrences(of: "\(path)/", with: "\(nextPath)/")
                    return copy
                }
                screen = .folder(nextPath)
                save()
            }
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFolder(path: String) async {
        do {
            if let client {
                try await client.deleteFolder(path: path)
                await refresh()
            } else {
                folders.removeAll { $0.path == path || $0.path.hasPrefix("\(path)/") }
                notes.removeAll { $0.folderPath == path || $0.folderPath.hasPrefix("\(path)/") }
                save()
            }
            screen = .home
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording(folderPath: String) {
        screen = .recording(folderPath)
        Task {
            await recorder.start()
        }
    }

    func stopRecording(folderPath: String) async {
        guard let result = await recorder.stop() else {
            screen = .folder(folderPath)
            return
        }

        do {
            if let client {
                let note = try await client.createNote(
                    folderPath: folderPath,
                    transcript: result.transcript,
                    audioURL: result.audioURL,
                    durationSeconds: result.durationSeconds
                )
                upsert(note: note)
                await refresh()
            } else {
                let note = localNote(folderPath: folderPath, transcript: result.transcript, duration: result.durationSeconds)
                upsert(note: note)
                incrementCount(for: folderPath)
                save()
            }
            screen = .folder(folderPath)
        } catch {
            errorMessage = error.localizedDescription
            screen = .folder(folderPath)
        }
    }

    func updateTranscript(notePath: String, transcript: String) async {
        do {
            if let client {
                let note = try await client.updateNote(path: notePath, transcript: transcript)
                upsert(note: note)
                await refresh()
            } else if let index = notes.firstIndex(where: { $0.path == notePath }) {
                notes[index].transcript = transcript
                save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveNote(path: String, to folderPath: String) async {
        do {
            if let client {
                let note = try await client.moveNote(path: path, folderPath: folderPath)
                upsert(note: note)
                await refresh()
                screen = .folder(folderPath)
            } else if let index = notes.firstIndex(where: { $0.path == path }) {
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                notes[index].folderPath = folderPath
                notes[index].path = "\(folderPath)/\(fileName)"
                refreshLocalCounts()
                save()
                screen = .folder(folderPath)
            }
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteNote(path: String) async {
        do {
            let folderPath = note(path: path)?.folderPath
            if let client {
                try await client.deleteNote(path: path)
                await refresh()
            } else {
                notes.removeAll { $0.path == path }
                refreshLocalCounts()
                save()
            }
            if let folderPath {
                screen = .folder(folderPath)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        pairing = nil
        isConnected = false
        statusText = "Not paired"
        save()
    }

    func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        save()
    }

    private func upsert(folder: BuddyFolder) {
        if let index = folders.firstIndex(where: { $0.path == folder.path }) {
            folders[index] = folder
        } else {
            folders.append(folder)
        }
    }

    private func upsert(note: BuddyNote) {
        if let index = notes.firstIndex(where: { $0.path == note.path }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
        refreshLocalCounts()
    }

    private func incrementCount(for folderPath: String) {
        if let index = folders.firstIndex(where: { $0.path == folderPath }) {
            folders[index].noteCount += 1
        }
    }

    private func refreshLocalCounts() {
        folders = folders.map { folder in
            var copy = folder
            copy.noteCount = notes.filter { $0.folderPath == folder.path || $0.folderPath.hasPrefix("\(folder.path)/") }.count
            return copy
        }
    }

    private func ensureFolderSelection() {
        if folders.isEmpty {
            folders = [BuddyFolder(path: "Voice Notes", name: "Voice Notes", noteCount: 0)]
        }
    }

    private func uniqueLocalFolderPath(_ name: String) -> String {
        var candidate = name
        var suffix = 1
        let existing = Set(folders.map(\.path))
        while existing.contains(candidate) {
            suffix += 1
            candidate = "\(name) \(suffix)"
        }
        return candidate
    }

    private func localNote(folderPath: String, transcript: String, duration: Double) -> BuddyNote {
        let date = Date()
        let title = transcript
            .split(whereSeparator: \.isWhitespace)
            .prefix(7)
            .joined(separator: " ")
        let fileName = "\(Self.pathDate(date)) \(title.isEmpty ? "Voice Note" : title).md"
        return BuddyNote(
            path: "\(folderPath)/\(fileName)",
            folderPath: folderPath,
            title: title.isEmpty ? "Voice Note" : title,
            transcript: transcript,
            recordedAt: date,
            durationSeconds: duration
        )
    }

    private func save() {
        store.save(
            BuddyState(
                folders: folders,
                notes: notes,
                pairing: pairing,
                appearance: appearance,
                hasCompletedWelcome: store.hasCompletedWelcome
            )
        )
    }

    private static func pathDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }

    private static func parentPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return "." }
        return parts.dropLast().joined(separator: "/")
    }
}

struct BuddyState: Codable {
    var folders: [BuddyFolder]
    var notes: [BuddyNote]
    var pairing: PairingInfo?
    var appearance: AppearanceMode
    var hasCompletedWelcome: Bool
}

private final class BuddyStore {
    private let defaults = UserDefaults.standard
    private let key = "forge-buddy-state-v1"
    var hasCompletedWelcome = false

    func load() -> BuddyState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(BuddyState.self, from: data)
        else {
            return BuddyState(folders: [], notes: [], pairing: nil, appearance: .system, hasCompletedWelcome: false)
        }
        hasCompletedWelcome = state.hasCompletedWelcome
        return state
    }

    func save(_ state: BuddyState) {
        hasCompletedWelcome = state.hasCompletedWelcome
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
