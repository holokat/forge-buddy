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
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSyncing = false
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
        refreshLocalCounts()
        updateStatusText()
    }

    var client: ForgeClient? {
        pairing.map(ForgeClient.init(pairing:))
    }

    var pendingItemCount: Int {
        folders.filter(\.needsSync).count + notes.filter(\.needsSync).count
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
        guard !isRefreshing else { return }
        guard let client else {
            isConnected = false
            updateStatusText()
            return
        }

        let previousFolders = folders
        let previousNotes = notes
        isRefreshing = true
        defer {
            isRefreshing = false
            updateStatusText()
        }

        do {
            statusText = "Syncing"
            let snapshot = try await client.snapshot()
            mergeRemoteSnapshot(
                folders: snapshot.0,
                notes: snapshot.1,
                previousFolders: previousFolders,
                previousNotes: previousNotes
            )
            ensureFolderSelection()
            reconcileNavigation(previousFolders: previousFolders, previousNotes: previousNotes)
            isConnected = true
            errorMessage = nil
            save()
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func syncNow() async {
        if pendingItemCount > 0 {
            await syncPending(showSuccess: true)
        } else {
            await refresh()
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
        if let localAudioFileName = note.localAudioFileName,
           let localURL = store.localAudioURL(fileName: localAudioFileName) {
            return localURL
        }
        guard let audioPath = note.audioPath else { return nil }
        return client?.audioURL(path: audioPath)
    }

    func mediaURL(for note: BuddyNote) -> URL? {
        if let localMediaFileName = note.localMediaFileName,
           let localURL = store.localMediaURL(fileName: localMediaFileName) {
            return localURL
        }
        guard let mediaPath = note.mediaPath else { return nil }
        return client?.mediaURL(path: mediaPath)
    }

    func createFolder(named rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let client {
            do {
                let folder = try await client.createFolder(name: name)
                upsert(folder: folder)
                await refresh()
            } catch {
                createLocalFolder(named: name, syncState: .failed, lastSyncError: error.localizedDescription)
                errorMessage = "Folder saved locally. Sync when your Mac is reachable."
            }
        } else {
            createLocalFolder(named: name, syncState: .pending)
        }
        sheet = nil
    }

    func renameFolder(path: String, to rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let shouldRenameLocally = client == nil || folder(path: path)?.needsSync == true

        if shouldRenameLocally {
            renameLocalFolder(path: path, to: name)
            sheet = nil
            return
        }

        do {
            if let client {
                let folder = try await client.renameFolder(path: path, newName: name)
                upsert(folder: folder)
                await refresh()
                screen = .folder(folder.path)
            }
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFolder(path: String) async {
        do {
            if folder(path: path)?.needsSync == true || client == nil {
                folders.removeAll { $0.path == path || $0.path.hasPrefix("\(path)/") }
                notes.removeAll { $0.folderPath == path || $0.folderPath.hasPrefix("\(path)/") }
                save()
                updateStatusText()
            } else if let client {
                try await client.deleteFolder(path: path)
                await refresh()
            }
            screen = .home
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording(folderPath: String, kind: BuddyNoteKind = .voice) {
        screen = .recording(folderPath, kind)
        Task {
            await recorder.start()
        }
    }

    func stopRecording(folderPath: String, kind: BuddyNoteKind = .voice) async {
        guard let result = await recorder.stop() else {
            screen = .folder(folderPath)
            return
        }

        do {
            let localAudioFileName = try store.persistRecording(from: result.audioURL)
            let title = kind == .agentTask
                ? Self.title(from: result.transcript, fallback: "Agent Task")
                : Self.title(from: result.transcript)
            let note = localNote(
                folderPath: folderPath,
                title: title,
                transcript: result.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                tags: kind.defaultTags,
                duration: result.durationSeconds,
                localAudioFileName: localAudioFileName,
                localMediaFileName: nil
            )
            upsert(note: note)
            save()
            screen = .folder(folderPath)
            if pairing != nil {
                await syncPending(showSuccess: false)
            } else {
                updateStatusText()
            }
        } catch {
            errorMessage = "The recording could not be saved locally: \(error.localizedDescription)"
            screen = .folder(folderPath)
        }
    }

    func updateTranscript(notePath: String, transcript: String) async {
        guard let index = notes.firstIndex(where: { $0.path == notePath }) else { return }

        if let client, !notes[index].needsSync {
            do {
                let note = try await client.updateNote(path: notePath, transcript: transcript)
                upsert(note: note)
                await refresh()
                return
            } catch {
                notes[index].lastSyncError = error.localizedDescription
                errorMessage = "Transcript saved locally. Sync when your Mac is reachable."
            }
        }

        notes[index].transcript = transcript
        if notes[index].kind == .voice {
            notes[index].title = Self.title(from: transcript)
        }
        if notes[index].pendingAction != .create {
            notes[index].pendingAction = .update
        }
        notes[index].syncState = .pending
        save()
        updateStatusText()
    }

    func createCaptureNote(
        folderPath: String,
        title rawTitle: String,
        body rawBody: String,
        kind: BuddyNoteKind,
        tags rawTags: [String],
        mediaData: Data? = nil,
        mediaFileExtension: String? = nil
    ) async {
        let title = Self.normalizedTitle(rawTitle, fallback: Self.defaultTitle(for: kind))
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || mediaData != nil else { return }

        do {
            let localMediaFileName = try mediaData.map {
                try store.persistMedia(data: $0, preferredExtension: mediaFileExtension)
            }
            let note = localNote(
                folderPath: folderPath,
                title: title,
                transcript: body,
                kind: kind,
                tags: Self.normalizedTags(rawTags, kind: kind),
                duration: nil,
                localAudioFileName: nil,
                localMediaFileName: localMediaFileName
            )
            upsert(note: note)
            save()
            sheet = nil
            screen = .folder(folderPath)
            if pairing != nil {
                await syncPending(showSuccess: false)
            } else {
                updateStatusText()
            }
        } catch {
            errorMessage = "The note could not be saved locally: \(error.localizedDescription)"
        }
    }

    func updateNoteTags(notePath: String, tags rawTags: [String]) async {
        guard let index = notes.firstIndex(where: { $0.path == notePath }) else { return }
        let tags = Self.normalizedTags(rawTags, kind: notes[index].kind)

        if let client, !notes[index].needsSync {
            do {
                let note = try await client.updateNote(path: notePath, tags: tags)
                upsert(note: note)
                await refresh()
                sheet = nil
                return
            } catch {
                notes[index].lastSyncError = error.localizedDescription
                errorMessage = "Tags saved locally. Sync when your Mac is reachable."
            }
        }

        notes[index].tags = tags
        if notes[index].pendingAction != .create {
            notes[index].pendingAction = .update
        }
        notes[index].syncState = .pending
        save()
        sheet = nil
        updateStatusText()
    }

    func moveNote(path: String, to folderPath: String) async {
        guard let index = notes.firstIndex(where: { $0.path == path }) else { return }
        let localMove = {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            self.notes[index].folderPath = folderPath
            self.notes[index].path = "\(folderPath)/\(fileName)"
            if self.notes[index].pendingAction != .create {
                self.notes[index].pendingAction = .move
                self.notes[index].syncState = .pending
            }
            self.refreshLocalCounts()
            self.save()
            self.screen = .folder(folderPath)
            self.sheet = nil
            self.updateStatusText()
        }

        if let client, !notes[index].needsSync {
            do {
                let note = try await client.moveNote(path: path, folderPath: folderPath)
                upsert(note: note)
                await refresh()
                screen = .folder(folderPath)
                sheet = nil
                return
            } catch {
                notes[index].lastSyncError = error.localizedDescription
                errorMessage = "Move saved locally. Sync when your Mac is reachable."
            }
        }

        localMove()
    }

    func deleteNote(path: String) async {
        do {
            guard let existing = note(path: path) else { return }
            let folderPath = existing.folderPath
            if existing.pendingAction == .create || client == nil {
                notes.removeAll { $0.path == path }
                refreshLocalCounts()
                save()
                updateStatusText()
            } else if let client {
                try await client.deleteNote(path: path)
                await refresh()
            }
            screen = .folder(folderPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        pairing = nil
        isConnected = false
        save()
        updateStatusText()
    }

    func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        save()
    }

    private func syncPending(showSuccess: Bool) async {
        guard !isSyncing else { return }
        guard let client else {
            isConnected = false
            updateStatusText()
            if showSuccess {
                errorMessage = "Pair a Mac to sync local notes into Forge."
            }
            return
        }

        isSyncing = true
        statusText = "Syncing"
        defer {
            isSyncing = false
            updateStatusText()
        }

        var syncedCount = 0
        var failedCount = 0

        for folder in folders.filter(\.needsSync) {
            guard let index = folders.firstIndex(where: { $0.path == folder.path }) else { continue }
            folders[index].syncState = .syncing
            do {
                let remote = try await client.createFolder(name: folder.name)
                replaceLocalFolder(path: folder.path, with: remote)
                syncedCount += 1
            } catch {
                if let remote = await matchingRemoteFolder(for: folder, client: client) {
                    replaceLocalFolder(path: folder.path, with: remote)
                    syncedCount += 1
                } else if let failureIndex = folders.firstIndex(where: { $0.path == folder.path }) {
                    folders[failureIndex].syncState = .failed
                    folders[failureIndex].lastSyncError = error.localizedDescription
                    failedCount += 1
                }
            }
        }

        for note in notes.filter(\.needsSync) {
            guard let current = self.note(path: note.path) else { continue }
            markNote(path: current.path, syncState: .syncing, error: nil)
            do {
                let remote = try await sync(note: current, client: client)
                replaceLocalNote(path: current.path, with: remote, preservingLocalAudioFrom: current)
                syncedCount += 1
            } catch {
                markNote(path: current.path, syncState: .failed, error: error.localizedDescription)
                failedCount += 1
            }
        }

        refreshLocalCounts()
        save()

        if failedCount > 0 && syncedCount == 0 {
            isConnected = false
        } else if syncedCount > 0 {
            isConnected = true
        }

        if syncedCount > 0 {
            await refresh()
        }

        if failedCount > 0, showSuccess {
            errorMessage = "\(failedCount) item\(failedCount == 1 ? "" : "s") could not sync. They remain saved locally."
        }
    }

    private func sync(note: BuddyNote, client: ForgeClient) async throws -> BuddyNote {
        switch note.pendingAction ?? .create {
        case .create:
            return try await client.createNote(
                folderPath: note.folderPath,
                title: note.title,
                transcript: note.transcript,
                kind: note.kind,
                tags: note.tags,
                audioURL: note.localAudioFileName.flatMap(store.localAudioURL(fileName:)),
                mediaURL: note.localMediaFileName.flatMap(store.localMediaURL(fileName:)),
                durationSeconds: note.durationSeconds,
                recordedAt: note.recordedAt ?? Date()
            )
        case .update:
            return try await client.updateNote(path: note.path, transcript: note.transcript, title: note.title, kind: note.kind, tags: note.tags)
        case .move:
            return try await client.moveNote(path: note.path, folderPath: note.folderPath)
        }
    }

    private func matchingRemoteFolder(for folder: BuddyFolder, client: ForgeClient) async -> BuddyFolder? {
        guard let snapshot = try? await client.snapshot() else { return nil }
        return snapshot.0.first { $0.path == folder.path || $0.name == folder.name }
    }

    private func mergeRemoteSnapshot(
        folders remoteFolders: [BuddyFolder],
        notes remoteNotes: [BuddyNote],
        previousFolders: [BuddyFolder],
        previousNotes: [BuddyNote]
    ) {
        let previousNotesByPath = Dictionary(uniqueKeysWithValues: previousNotes.map { ($0.path, $0) })
        var mergedFolders = remoteFolders.map { remote in
            var copy = remote
            copy.syncState = .synced
            copy.lastSyncError = nil
            return copy
        }

        for local in previousFolders where local.needsSync && !mergedFolders.contains(where: { $0.path == local.path }) {
            mergedFolders.append(local)
        }

        var mergedNotes = remoteNotes.map { remote in
            var copy = remote
            copy.localAudioFileName = previousNotesByPath[remote.path]?.localAudioFileName
            copy.localMediaFileName = previousNotesByPath[remote.path]?.localMediaFileName
            copy.syncState = .synced
            copy.pendingAction = nil
            copy.lastSyncError = nil
            return copy
        }

        for local in previousNotes where local.needsSync && !mergedNotes.contains(where: { $0.path == local.path }) {
            mergedNotes.append(local)
        }

        folders = mergedFolders.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        notes = mergedNotes.sorted {
            ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast)
        }
        refreshLocalCounts()
    }

    private func replaceLocalFolder(path localPath: String, with remote: BuddyFolder) {
        var synced = remote
        synced.syncState = .synced
        synced.lastSyncError = nil

        if let index = folders.firstIndex(where: { $0.path == localPath }) {
            folders[index] = synced
        } else {
            upsert(folder: synced)
        }

        guard localPath != synced.path else { return }
        notes = notes.map { note in
            guard note.folderPath == localPath || note.folderPath.hasPrefix("\(localPath)/") else { return note }
            var copy = note
            copy.folderPath = copy.folderPath.replacingOccurrences(of: localPath, with: synced.path)
            copy.path = copy.path.replacingOccurrences(of: "\(localPath)/", with: "\(synced.path)/")
            return copy
        }
    }

    private func replaceLocalNote(path localPath: String, with remote: BuddyNote, preservingLocalAudioFrom local: BuddyNote) {
        var synced = remote
        synced.localAudioFileName = local.localAudioFileName
        synced.localMediaFileName = local.localMediaFileName
        synced.syncState = .synced
        synced.pendingAction = nil
        synced.lastSyncError = nil

        if let index = notes.firstIndex(where: { $0.path == localPath }) {
            notes[index] = synced
        } else {
            upsert(note: synced)
        }
    }

    private func markNote(path: String, syncState: BuddySyncState, error: String?) {
        guard let index = notes.firstIndex(where: { $0.path == path }) else { return }
        notes[index].syncState = syncState
        notes[index].lastSyncError = error
    }

    private func createLocalFolder(named name: String, syncState: BuddySyncState, lastSyncError: String? = nil) {
        let path = uniqueLocalFolderPath(name)
        folders.append(BuddyFolder(path: path, name: name, noteCount: 0, syncState: syncState, lastSyncError: lastSyncError))
        save()
        updateStatusText()
    }

    private func renameLocalFolder(path: String, to name: String) {
        guard let index = folders.firstIndex(where: { $0.path == path }) else { return }
        let parent = Self.parentPath(path)
        let nextPath = parent == "." ? uniqueLocalFolderPath(name) : "\(parent)/\(name)"
        let currentSyncState = folders[index].syncState == .synced ? BuddySyncState.pending : folders[index].syncState
        folders[index].path = nextPath
        folders[index].name = name
        folders[index].syncState = currentSyncState
        notes = notes.map { note in
            guard note.folderPath == path || note.folderPath.hasPrefix("\(path)/") else { return note }
            var copy = note
            copy.folderPath = copy.folderPath.replacingOccurrences(of: path, with: nextPath)
            copy.path = copy.path.replacingOccurrences(of: "\(path)/", with: "\(nextPath)/")
            return copy
        }
        screen = .folder(nextPath)
        refreshLocalCounts()
        save()
        updateStatusText()
    }

    private func upsert(folder: BuddyFolder) {
        if let index = folders.firstIndex(where: { $0.path == folder.path }) {
            var next = folder
            if next.syncState == .synced {
                next.lastSyncError = nil
            }
            folders[index] = next
        } else {
            folders.append(folder)
        }
    }

    private func upsert(note: BuddyNote) {
        if let index = notes.firstIndex(where: { $0.path == note.path }) {
            var next = note
            if next.localAudioFileName == nil {
                next.localAudioFileName = notes[index].localAudioFileName
            }
            if next.localMediaFileName == nil {
                next.localMediaFileName = notes[index].localMediaFileName
            }
            if next.syncState == .synced {
                next.pendingAction = nil
                next.lastSyncError = nil
            }
            notes[index] = next
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

    private func reconcileNavigation(previousFolders: [BuddyFolder], previousNotes: [BuddyNote]) {
        switch screen {
        case .folder(let path):
            if !folderExists(path) {
                screen = remappedFolderPath(for: path, previousFolders: previousFolders, previousNotes: previousNotes)
                    .map(AppScreen.folder) ?? .home
            }
        case .detail(let path):
            if !noteExists(path) {
                if let nextPath = remappedNotePath(for: path, previousNotes: previousNotes) {
                    screen = .detail(nextPath)
                } else {
                    screen = .home
                }
            }
        case .recording:
            break
        default:
            break
        }

        switch sheet {
        case .folderOptions(let path):
            sheet = reconciledFolderSheet(.folderOptions(path), previousFolders: previousFolders, previousNotes: previousNotes)
        case .renameFolder(let path):
            sheet = reconciledFolderSheet(.renameFolder(path), previousFolders: previousFolders, previousNotes: previousNotes)
        case .deleteFolder(let path):
            sheet = reconciledFolderSheet(.deleteFolder(path), previousFolders: previousFolders, previousNotes: previousNotes)
        case .moveNote(let path):
            if !noteExists(path) {
                sheet = remappedNotePath(for: path, previousNotes: previousNotes).map(BuddySheet.moveNote)
            }
        default:
            break
        }
    }

    private func reconciledFolderSheet(
        _ current: BuddySheet,
        previousFolders: [BuddyFolder],
        previousNotes: [BuddyNote]
    ) -> BuddySheet? {
        let path: String
        switch current {
        case .folderOptions(let value), .renameFolder(let value), .deleteFolder(let value):
            path = value
        default:
            return current
        }

        let nextPath: String?
        if folderExists(path) {
            nextPath = path
        } else {
            nextPath = remappedFolderPath(for: path, previousFolders: previousFolders, previousNotes: previousNotes)
        }

        guard let nextPath else { return nil }
        switch current {
        case .folderOptions:
            return .folderOptions(nextPath)
        case .renameFolder:
            return .renameFolder(nextPath)
        case .deleteFolder:
            return .deleteFolder(nextPath)
        default:
            return current
        }
    }

    private func remappedFolderPath(
        for path: String,
        previousFolders: [BuddyFolder],
        previousNotes: [BuddyNote]
    ) -> String? {
        let previousPaths = Set(previousFolders.map(\.path))
        let currentPaths = Set(folders.map(\.path))
        let removedPaths = previousPaths.subtracting(currentPaths)
        let addedPaths = currentPaths.subtracting(previousPaths)
        if removedPaths.count == 1, removedPaths.contains(path), addedPaths.count == 1 {
            return addedPaths.first
        }

        let oldNoteNames = Set(previousNotes
            .filter { noteBelongs($0.folderPath, to: path) }
            .map { Self.fileName($0.path) })
        guard !oldNoteNames.isEmpty else { return nil }

        let matchesByFolder = Dictionary(grouping: notes.filter { oldNoteNames.contains(Self.fileName($0.path)) }) {
            $0.folderPath
        }
        return matchesByFolder
            .filter { folderExists($0.key) }
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private func remappedNotePath(for path: String, previousNotes: [BuddyNote]) -> String? {
        guard let previous = previousNotes.first(where: { $0.path == path }) else { return nil }
        let previousFileName = Self.fileName(previous.path)
        return notes.first {
            Self.fileName($0.path) == previousFileName &&
            $0.recordedAt == previous.recordedAt &&
            $0.title == previous.title
        }?.path ?? notes.first {
            Self.fileName($0.path) == previousFileName &&
            $0.title == previous.title
        }?.path
    }

    private func folderExists(_ path: String) -> Bool {
        folders.contains { $0.path == path }
    }

    private func noteExists(_ path: String) -> Bool {
        notes.contains { $0.path == path }
    }

    private func noteBelongs(_ folderPath: String, to path: String) -> Bool {
        folderPath == path || folderPath.hasPrefix("\(path)/")
    }

    private static func fileName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
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

    private func localNote(
        folderPath: String,
        title: String,
        transcript: String,
        kind: BuddyNoteKind,
        tags: [String],
        duration: Double?,
        localAudioFileName: String?,
        localMediaFileName: String?
    ) -> BuddyNote {
        let date = Date()
        let fileName = "\(Self.pathDate(date)) \(Self.safeFileComponent(title)).md"
        return BuddyNote(
            path: uniqueLocalNotePath(folderPath: folderPath, fileName: fileName),
            folderPath: folderPath,
            title: title,
            transcript: transcript,
            kind: kind,
            tags: tags,
            recordedAt: date,
            durationSeconds: duration,
            localAudioFileName: localAudioFileName,
            localMediaFileName: localMediaFileName,
            syncState: .pending,
            pendingAction: .create
        )
    }

    private func uniqueLocalNotePath(folderPath: String, fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        var candidate = "\(folderPath)/\(fileName)"
        var suffix = 1
        let existing = Set(notes.map(\.path))
        while existing.contains(candidate) {
            suffix += 1
            let nextFileName = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = "\(folderPath)/\(nextFileName)"
        }
        return candidate
    }

    private func updateStatusText() {
        if pendingItemCount > 0 {
            statusText = "\(pendingItemCount) pending"
        } else if isSyncing || isRefreshing {
            statusText = "Syncing"
        } else if isConnected {
            statusText = "Connected"
        } else if pairing == nil {
            statusText = "Local only"
        } else {
            statusText = "Offline"
        }
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

    private static func title(from transcript: String, fallback: String = "Voice Note") -> String {
        let title = transcript
            .split(whereSeparator: \.isWhitespace)
            .prefix(7)
            .joined(separator: " ")
        return title.isEmpty ? fallback : title
    }

    private static func defaultTitle(for kind: BuddyNoteKind) -> String {
        switch kind {
        case .voice: return "Voice Note"
        case .text: return "Text Note"
        case .template: return "Template Note"
        case .agentTask: return "Agent Task"
        case .media: return "Media Note"
        }
    }

    private static func normalizedTitle(_ value: String, fallback: String) -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }

    private static func normalizedTags(_ tags: [String], kind: BuddyNoteKind) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in kind.defaultTags + tags {
            let cleaned = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
                .replacingOccurrences(of: "[^a-z0-9_/-]", with: "", options: .regularExpression)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }
        return result
    }

    private static func safeFileComponent(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Voice Note" : cleaned
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
    private let fileManager = FileManager.default
    var hasCompletedWelcome = false

    var recordingsDirectory: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("Forge Buddy", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    var mediaDirectory: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("Forge Buddy", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

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

    func persistRecording(from sourceURL: URL) throws -> String {
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let targetURL = recordingsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
        return fileName
    }

    func persistMedia(data: Data, preferredExtension: String?) throws -> String {
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let ext = Self.safeMediaExtension(preferredExtension, data: data)
        let fileName = "\(UUID().uuidString).\(ext)"
        let targetURL = mediaDirectory.appendingPathComponent(fileName)
        try data.write(to: targetURL, options: .atomic)
        return fileName
    }

    func localAudioURL(fileName: String) -> URL? {
        let url = recordingsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func localMediaURL(fileName: String) -> URL? {
        let url = mediaDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private static func safeMediaExtension(_ preferredExtension: String?, data: Data) -> String {
        let cleaned = (preferredExtension ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t"))
            .lowercased()
        if ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(cleaned) {
            return cleaned
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "jpg"
    }
}
