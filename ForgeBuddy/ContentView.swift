import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            ForgeTheme.background.ignoresSafeArea()
            switch model.screen {
            case .welcome:
                WelcomeView()
            case .scan:
                ScanView()
            case .connecting:
                ConnectingView()
            case .paired:
                PairedView()
            case .home:
                HomeView()
            case .folder(let path):
                FolderView(folderPath: path)
            case .recording(let path):
                RecordingView(folderPath: path)
            case .detail(let path):
                NoteDetailView(notePath: path)
            case .settings:
                SettingsView()
            }
        }
        .foregroundStyle(ForgeTheme.text)
        .sheet(item: $model.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(model)
                .presentationDragIndicator(.visible)
        }
        .alert("Forge Buddy", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            await model.refresh()
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            LogoTile(size: 78, radius: 23)
            Text("Forge")
                .font(.system(size: 35, weight: .semibold))
                .tracking(-1)
            Text("Speak a note - it's transcribed and synced to your Mac in seconds.")
                .font(.forgeBody(16))
                .foregroundStyle(ForgeTheme.soft)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
            Spacer()
            VStack(spacing: 8) {
                PrimaryButton(title: "Connect your Mac") {
                    model.beginPairing()
                }
                Button("Set up later") {
                    model.completeWelcome()
                }
                .font(.forgeBody(15, weight: .semibold))
                .foregroundStyle(ForgeTheme.faint)
                .frame(height: 46)
                .buttonStyle(PressButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }
}

struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scanLineDown = false
    @State private var manualEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                model.screen = .welcome
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.forgeBody(15, weight: .semibold))
            }
            .foregroundStyle(ForgeTheme.secondary)
            .buttonStyle(PressButtonStyle())

            VStack(alignment: .leading, spacing: 8) {
                Text("Scan to connect")
                    .font(.forgeTitle(30))
                    .tracking(-0.9)
                Text("Scan the QR code shown in Forge settings on your Mac.")
                    .font(.forgeBody(16))
                    .foregroundStyle(ForgeTheme.soft)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black)
                QRScannerView { code in
                    if let url = URL(string: code) {
                        model.handlePairingURL(url)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                ScannerCorners()
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 168, height: 168)
                Rectangle()
                    .fill(ForgeTheme.green)
                    .frame(width: 176, height: 2)
                    .shadow(color: ForgeTheme.green.opacity(0.7), radius: 10, y: 0)
                    .offset(y: scanLineDown ? 74 : -74)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: scanLineDown)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onAppear { scanLineDown = true }

            HStack(spacing: 8) {
                BlinkingDot(color: ForgeTheme.green, size: 7)
                Text("Looking for a code...")
                    .font(.forgeBody(13, weight: .medium))
                    .foregroundStyle(ForgeTheme.soft)
                Spacer()
            }

            SecondaryButton(title: "Enter code manually", symbol: "keyboard") {
                manualEntry = true
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .sheet(isPresented: $manualEntry) {
            ManualPairingSheet()
                .environmentObject(model)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
    }
}

struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(ForgeTheme.ink)
                .scaleEffect(1.7)
                .frame(width: 58, height: 58)
            Text("Connecting...")
                .font(.forgeTitle(25))
            Text("Pairing this phone with your Mac.")
                .font(.forgeBody(16))
                .foregroundStyle(ForgeTheme.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

struct PairedView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(ForgeTheme.successTint)
                Image(systemName: "checkmark")
                    .font(.system(size: 33, weight: .bold))
                    .foregroundStyle(ForgeTheme.green)
            }
            .frame(width: 82, height: 82)

            VStack(spacing: 8) {
                Text("You're connected")
                    .font(.forgeTitle(29))
                    .tracking(-0.7)
                Text("Recordings and folders will save straight into Forge.")
                    .font(.forgeBody(16))
                    .foregroundStyle(ForgeTheme.soft)
                    .multilineTextAlignment(.center)
            }

            DeviceCard()
            Spacer()
            PrimaryButton(title: "Start using Forge") {
                model.finishPairedScreen()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            TopChrome()

            HStack {
                Text("Folders")
                    .font(.forgeTitle())
                    .tracking(-0.9)
                Spacer()
                IconButton(symbol: "folder.badge.plus", size: 38) {
                    model.sheet = .newFolder
                }
            }

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.folders.enumerated()), id: \.element.id) { index, folder in
                        FolderRow(folder: folder, color: ForgeTheme.folderColor(for: index)) {
                            model.screen = .folder(folder.path)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}

struct FolderView: View {
    @EnvironmentObject private var model: AppModel
    let folderPath: String
    @State private var pulse = false

    var folder: BuddyFolder? { model.folder(path: folderPath) }
    var notes: [BuddyNote] { model.notes(in: folderPath) }
    var folderIndex: Int { model.folders.firstIndex(where: { $0.path == folderPath }) ?? 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 20) {
                HStack {
                    Button {
                        model.screen = .home
                    } label: {
                        Label("Folders", systemImage: "chevron.left")
                            .font(.forgeBody(15, weight: .semibold))
                    }
                    .foregroundStyle(ForgeTheme.secondary)
                    .buttonStyle(PressButtonStyle())
                    Spacer()
                    RefreshIconButton(size: 34)
                    IconButton(symbol: "ellipsis", size: 34) {
                        model.sheet = .folderOptions(folderPath)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        FolderIcon(color: ForgeTheme.folderColor(for: folderIndex), size: 34)
                        Text(folder?.name ?? "Folder")
                            .font(.forgeTitle(29))
                            .tracking(-0.8)
                            .lineLimit(1)
                    }
                    Text(notes.isEmpty ? "No notes yet" : "\(notes.count) \(notes.count == 1 ? "note" : "notes")")
                        .font(.forgeBody(13, weight: .medium))
                        .foregroundStyle(ForgeTheme.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if notes.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("Nothing here yet")
                            .font(.forgeBody(16, weight: .semibold))
                        Text("Record a note into this folder.")
                            .font(.forgeBody(14))
                            .foregroundStyle(ForgeTheme.soft)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(notes) { note in
                                NoteRow(note: note) {
                                    model.screen = .detail(note.path)
                                }
                            }
                        }
                        .padding(.bottom, 160)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            VStack(spacing: 12) {
                RecordingChip(folderName: folder?.name ?? "Folder", color: ForgeTheme.folderColor(for: folderIndex))
                Button {
                    model.startRecording(folderPath: folderPath)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(ForgeTheme.ink.opacity(0.16), lineWidth: 9)
                            .scaleEffect(pulse ? 1.26 : 1)
                            .opacity(pulse ? 0 : 1)
                            .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false), value: pulse)
                        Circle().fill(ForgeTheme.ink)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(ForgeTheme.onInk)
                    }
                    .frame(width: 86, height: 86)
                }
                .buttonStyle(PressButtonStyle(pressedScale: 0.96))
            }
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [ForgeTheme.background.opacity(0), ForgeTheme.background, ForgeTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 154)
                .offset(y: 20),
                alignment: .bottom
            )
            .onAppear { pulse = true }
        }
    }
}

struct RecordingView: View {
    @EnvironmentObject private var model: AppModel
    let folderPath: String

    var body: some View {
        RecordingContent(recorder: model.recorder, folderPath: folderPath)
    }
}

private struct RecordingContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var recorder: RecorderService
    let folderPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    BlinkingDot(color: ForgeTheme.red, size: 8)
                    Text("Recording")
                        .font(.forgeBody(15, weight: .semibold))
                        .foregroundStyle(ForgeTheme.red)
                }
                Spacer()
                Text(formatDuration(recorder.elapsedSeconds))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ForgeTheme.secondary)
            }

            RecordingChip(
                folderName: model.folder(path: folderPath)?.name ?? "Folder",
                color: ForgeTheme.folderColor(for: folderPath, folders: model.folders)
            )

            ScrollView {
                Text(recorder.transcript.isEmpty ? "Listening... start speaking." : recorder.transcript)
                    .font(.system(size: 22, weight: .regular))
                    .lineSpacing(7)
                    .foregroundStyle(recorder.transcript.isEmpty ? ForgeTheme.faint : ForgeTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)
            }

            WaveformView(levels: recorder.levels, color: ForgeTheme.ink)
                .frame(height: 56)

            VStack(spacing: 13) {
                Text(recorder.errorMessage ?? recorder.statusMessage)
                    .font(.forgeBody(13, weight: .medium))
                    .foregroundStyle(recorder.errorMessage == nil ? ForgeTheme.soft : ForgeTheme.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await model.stopRecording(folderPath: folderPath) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(ForgeTheme.red)
                            .shadow(color: ForgeTheme.red.opacity(0.42), radius: 18, y: 10)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                    }
                    .frame(width: 86, height: 86)
                }
                .buttonStyle(PressButtonStyle(pressedScale: 0.96))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }
}

struct NoteDetailView: View {
    @EnvironmentObject private var model: AppModel
    let notePath: String
    @State private var draft = ""
    @State private var copied = false
    @State private var editing = false
    @StateObject private var audioPlayer = BuddyAudioPlayer()

    var note: BuddyNote? { model.note(path: notePath) }
    var folder: BuddyFolder? { note.flatMap { model.folder(path: $0.folderPath) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    if let folderPath = note?.folderPath {
                        model.screen = .folder(folderPath)
                    } else {
                        model.screen = .home
                    }
                } label: {
                    Label(folder?.name ?? "Folder", systemImage: "chevron.left")
                        .font(.forgeBody(15, weight: .semibold))
                }
                .foregroundStyle(ForgeTheme.secondary)
                .buttonStyle(PressButtonStyle())
                Spacer()
                RefreshIconButton(size: 34)
            }

            if let note {
                Text("\(relativeTime(note.recordedAt)) · \(formatDuration(note.durationSeconds ?? 0))")
                    .font(.forgeBody(13, weight: .medium))
                    .foregroundStyle(ForgeTheme.faint)

                if let audioURL = model.audioURL(for: note) {
                    AudioPlaybackCard(
                        url: audioURL,
                        duration: note.durationSeconds,
                        player: audioPlayer
                    )
                }

                if editing {
                    TextEditor(text: $draft)
                        .font(.system(size: 19))
                        .lineSpacing(7)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ScrollView {
                        Text(note.transcript.isEmpty ? "Transcript unavailable. Play the recording above." : note.transcript)
                            .font(.system(size: 19, weight: .regular))
                            .lineSpacing(8)
                            .foregroundStyle(note.transcript.isEmpty ? ForgeTheme.soft : ForgeTheme.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = note.transcript
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryPillStyle())

                    if editing {
                        IconButton(symbol: "checkmark", size: 46) {
                            Task {
                                await model.updateTranscript(notePath: note.path, transcript: draft)
                                editing = false
                            }
                        }
                    } else {
                        IconButton(symbol: "pencil", size: 46) {
                            draft = note.transcript
                            editing = true
                        }
                    }

                    IconButton(symbol: "folder", size: 46) {
                        model.sheet = .moveNote(note.path)
                    }

                    IconButton(symbol: "trash", size: 46, tint: ForgeTheme.red) {
                        Task { await model.deleteNote(path: note.path) }
                    }
                }
                .padding(.bottom, 22)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .onAppear {
            draft = note?.transcript ?? ""
        }
    }
}

struct AudioPlaybackCard: View {
    let url: URL
    let duration: Double?
    @ObservedObject var player: BuddyAudioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    player.toggle(url: url)
                } label: {
                    ZStack {
                        Circle()
                            .fill(ForgeTheme.ink)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ForgeTheme.onInk)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(PressButtonStyle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Recording")
                        .font(.forgeBody(15, weight: .semibold))
                    Text(duration.map(formatDuration) ?? "Audio note")
                        .font(.forgeBody(12.5, weight: .medium))
                        .foregroundStyle(ForgeTheme.soft)
                }
                Spacer()
            }

            if let error = player.errorMessage {
                Text(error)
                    .font(.forgeBody(12.5, weight: .medium))
                    .foregroundStyle(ForgeTheme.red)
            }
        }
        .padding(12)
        .background(ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ForgeTheme.border, lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Button {
                    model.screen = .home
                } label: {
                    Label("Done", systemImage: "chevron.left")
                        .font(.forgeBody(15, weight: .semibold))
                }
                .foregroundStyle(ForgeTheme.secondary)
                .buttonStyle(PressButtonStyle())

                Text("Settings")
                    .font(.forgeTitle())
                    .tracking(-0.9)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("APPEARANCE")
                    HStack(spacing: 4) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Button {
                                model.setAppearance(mode)
                            } label: {
                                Label(mode.title, systemImage: mode.symbol)
                                    .font(.forgeBody(13.5, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .foregroundStyle(model.appearance == mode ? ForgeTheme.text : ForgeTheme.soft)
                                    .background(
                                        Group {
                                            if model.appearance == mode {
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(ForgeTheme.background)
                                                    .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(PressButtonStyle(pressedScale: 0.98))
                        }
                    }
                    .padding(4)
                    .background(ForgeTheme.rowHover, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(ForgeTheme.border, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("PAIRED MAC")
                    if model.pairing != nil {
                        DeviceCard()
                        if !model.isConnected {
                            PrimaryButton(title: "Reconnect") {
                                Task { await model.refresh() }
                            }
                        }
                        SecondaryButton(title: "Pair a different Mac", symbol: "qrcode") {
                            model.screen = .scan
                        }
                        Button {
                            model.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                                .font(.forgeBody(15, weight: .semibold))
                                .foregroundStyle(ForgeTheme.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(ForgeTheme.destructiveTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(ForgeTheme.destructiveBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(PressButtonStyle())
                    } else {
                        VStack(spacing: 14) {
                            Text("No Mac paired")
                                .font(.forgeBody(16, weight: .semibold))
                            PrimaryButton(title: "Pair a Mac") {
                                model.screen = .scan
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
    }
}

struct SheetHost: View {
    let sheet: BuddySheet

    var body: some View {
        switch sheet {
        case .newFolder:
            NewFolderSheet()
                .presentationDetents([.height(240)])
        case .moveNote(let path):
            MoveNoteSheet(notePath: path)
                .presentationDetents([.medium])
        case .folderOptions(let path):
            FolderOptionsSheet(folderPath: path)
                .presentationDetents([.height(260)])
        case .renameFolder(let path):
            RenameFolderSheet(folderPath: path)
                .presentationDetents([.height(240)])
        case .deleteFolder(let path):
            DeleteFolderSheet(folderPath: path)
                .presentationDetents([.height(250)])
        }
    }
}

struct NewFolderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        SheetScaffold(title: "New Folder") {
            TextField("Folder name", text: $name)
                .textInputAutocapitalization(.words)
                .font(.forgeBody(15))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(ForgeTheme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                SecondaryButton(title: "Cancel") { dismiss() }
                PrimaryButton(title: "Create") {
                    Task { await model.createFolder(named: name) }
                }
            }
        }
    }
}

struct RenameFolderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let folderPath: String
    @State private var name = ""

    var body: some View {
        SheetScaffold(title: "Rename Folder") {
            TextField("Folder name", text: $name)
                .textInputAutocapitalization(.words)
                .font(.forgeBody(15))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(ForgeTheme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear { name = model.folder(path: folderPath)?.name ?? "" }
            HStack(spacing: 10) {
                SecondaryButton(title: "Cancel") { dismiss() }
                PrimaryButton(title: "Save") {
                    Task { await model.renameFolder(path: folderPath, to: name) }
                }
            }
        }
    }
}

struct DeleteFolderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let folderPath: String

    var folder: BuddyFolder? { model.folder(path: folderPath) }
    var count: Int { model.notes(in: folderPath).count }

    var body: some View {
        SheetScaffold(title: "Delete \"\(folder?.name ?? "Folder")\"?") {
            Text(count == 0 ? "This folder is empty." : "This will also delete \(count) note\(count == 1 ? "" : "s") inside it.")
                .font(.forgeBody(15))
                .foregroundStyle(ForgeTheme.soft)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                SecondaryButton(title: "Cancel") { dismiss() }
                Button {
                    Task { await model.deleteFolder(path: folderPath) }
                } label: {
                    Text("Delete")
                        .font(.forgeBody(15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(ForgeTheme.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressButtonStyle())
            }
        }
    }
}

struct MoveNoteSheet: View {
    @EnvironmentObject private var model: AppModel
    let notePath: String

    var body: some View {
        SheetScaffold(title: "Move to folder") {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.folders.enumerated()), id: \.element.id) { index, folder in
                        Button {
                            Task { await model.moveNote(path: notePath, to: folder.path) }
                        } label: {
                            HStack(spacing: 10) {
                                FolderIcon(color: ForgeTheme.folderColor(for: index), size: 28)
                                Text(folder.name)
                                    .font(.forgeBody(15, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                if model.note(path: notePath)?.folderPath == folder.path {
                                    Text("Current")
                                        .font(.forgeBody(12, weight: .semibold))
                                        .foregroundStyle(ForgeTheme.green)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(
                                model.note(path: notePath)?.folderPath == folder.path ? ForgeTheme.successTint : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                        }
                        .foregroundStyle(ForgeTheme.text)
                        .buttonStyle(PressButtonStyle(pressedScale: 0.98))
                    }
                }
            }
        }
    }
}

struct FolderOptionsSheet: View {
    @EnvironmentObject private var model: AppModel
    let folderPath: String

    var body: some View {
        SheetScaffold(title: nil) {
            HStack(spacing: 12) {
                FolderIcon(color: ForgeTheme.folderColor(for: folderPath, folders: model.folders), size: 38)
                Text(model.folder(path: folderPath)?.name ?? "Folder")
                    .font(.forgeBody(17, weight: .semibold))
                Spacer()
            }
            OptionRow(title: "Rename folder", symbol: "pencil") {
                model.sheet = .renameFolder(folderPath)
            }
            OptionRow(title: "Delete folder", symbol: "trash", destructive: true) {
                model.sheet = .deleteFolder(folderPath)
            }
        }
    }
}

struct ManualPairingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        SheetScaffold(title: "Enter pairing link") {
            TextField("forge-buddy://pair?...", text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.forgeBody(15))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(ForgeTheme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            PrimaryButton(title: "Connect") {
                if let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    dismiss()
                    model.handlePairingURL(url)
                }
            }
        }
    }
}

struct TopChrome: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            LogoTile(size: 30, radius: 9)
            Text("Forge")
                .font(.forgeBody(17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isConnected ? ForgeTheme.green : ForgeTheme.faint)
                    .frame(width: 7, height: 7)
                Text(model.statusText)
                    .font(.forgeBody(12.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(model.isConnected ? ForgeTheme.successTint : ForgeTheme.subtleSurface, in: Capsule())

            RefreshIconButton(size: 34)

            IconButton(symbol: "gearshape", size: 34) {
                model.screen = .settings
            }
        }
    }
}

struct DeviceCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ForgeTheme.blue.opacity(0.14))
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(ForgeTheme.blue)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.pairing?.desktop ?? "Forge for Mac")
                        .font(.forgeBody(15, weight: .semibold))
                    Text(model.pairing?.baseURL.host() ?? "No address")
                        .font(.forgeBody(12.5, weight: .medium))
                        .foregroundStyle(ForgeTheme.soft)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isConnected ? ForgeTheme.green : ForgeTheme.faint)
                        .frame(width: 6, height: 6)
                    Text(model.isConnected ? "Live" : "Offline")
                        .font(.forgeBody(12, weight: .semibold))
                        .foregroundStyle(model.isConnected ? ForgeTheme.green : ForgeTheme.soft)
                }
            }

            Divider().overlay(ForgeTheme.border)

            HStack {
                Text("Address")
                    .foregroundStyle(ForgeTheme.soft)
                Spacer()
                Text(model.pairing?.baseURL.absoluteString ?? "-")
                    .lineLimit(1)
            }
            .font(.forgeBody(12.5, weight: .medium))

            HStack {
                Text("Paired")
                    .foregroundStyle(ForgeTheme.soft)
                Spacer()
                Text(relativeTime(model.pairing?.pairedAt))
            }
            .font(.forgeBody(12.5, weight: .medium))
        }
        .padding(14)
        .background(ForgeTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ForgeTheme.cardBorder, lineWidth: 1)
        )
    }
}

struct FolderRow: View {
    let folder: BuddyFolder
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FolderIcon(color: color, size: 26)
                Text(folder.name)
                    .font(.forgeBody(15, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(folder.noteCount)")
                    .font(.forgeBody(12.5, weight: .semibold))
                    .foregroundStyle(ForgeTheme.faint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ForgeTheme.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .foregroundStyle(ForgeTheme.text)
        .buttonStyle(RowButtonStyle())
    }
}

struct NoteRow: View {
    let note: BuddyNote
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ForgeTheme.tertiary)
                    .frame(width: 22)
                Text(note.transcript.isEmpty ? note.title : note.transcript)
                    .font(.forgeBody(15, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(relativeTime(note.recordedAt)) · \(formatDuration(note.durationSeconds ?? 0))")
                    .font(.forgeBody(12.5, weight: .medium))
                    .foregroundStyle(ForgeTheme.faint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
        }
        .foregroundStyle(ForgeTheme.text)
        .buttonStyle(RowButtonStyle())
    }
}

struct FolderIcon: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(8, size * 0.32), style: .continuous)
                .fill(color.opacity(0.13))
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct LogoTile: View {
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(ForgeTheme.ink)
            Image(systemName: "hexagon.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(ForgeTheme.onInk)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: size, height: size)
    }
}

struct RecordingChip: View {
    let folderName: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("Recording to \(folderName)")
                .font(.forgeBody(13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(height: 32)
        .background(ForgeTheme.chip, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.forgeBody(15, weight: .semibold))
                .foregroundStyle(ForgeTheme.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(ForgeTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressButtonStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.forgeBody(15, weight: .semibold))
            .foregroundStyle(ForgeTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ForgeTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressButtonStyle())
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 40
    var tint: Color = ForgeTheme.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: max(14, size * 0.42), weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: min(13, size * 0.29), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: min(13, size * 0.29), style: .continuous)
                        .stroke(ForgeTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(PressButtonStyle())
    }
}

struct RefreshIconButton: View {
    @EnvironmentObject private var model: AppModel
    var size: CGFloat = 40

    var body: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            ZStack {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ForgeTheme.secondary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: max(14, size * 0.4), weight: .semibold))
                        .foregroundStyle(ForgeTheme.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: min(13, size * 0.29), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: min(13, size * 0.29), style: .continuous)
                    .stroke(ForgeTheme.border, lineWidth: 1)
            )
        }
        .disabled(model.isRefreshing)
        .buttonStyle(PressButtonStyle())
        .accessibilityLabel("Refresh")
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(ForgeTheme.faint)
    }
}

struct OptionRow: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.forgeBody(15, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(destructive ? ForgeTheme.red : ForgeTheme.text)
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(destructive ? ForgeTheme.destructiveTint : ForgeTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressButtonStyle())
    }
}

struct SheetScaffold<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            if let title {
                Text(title)
                    .font(.forgeBody(18, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ForgeTheme.background)
    }
}

struct WaveformView: View {
    let levels: [CGFloat]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let count = max(levels.count, 1)
            let width = max(3, (proxy.size.width - CGFloat(count - 1) * spacing) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                        .fill(color.opacity(0.9))
                        .frame(width: width, height: max(5, proxy.size.height * level))
                }
            }
            .animation(.easeOut(duration: 0.08), value: levels)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ScannerCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 32
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

struct BlinkingDot: View {
    let color: Color
    let size: CGFloat
    @State private var visible = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(visible ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}

struct PressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ForgeTheme.rowHover : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PrimaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.forgeBody(15, weight: .semibold))
            .foregroundStyle(ForgeTheme.onInk)
            .frame(height: 46)
            .background(ForgeTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return "\(total / 60):\(String(format: "%02d", total % 60))"
}

func relativeTime(_ date: Date?) -> String {
    guard let date else { return "Now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}
