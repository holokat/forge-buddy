import AVFoundation
import Foundation
import Speech

@MainActor
final class RecorderService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.12, count: 34)
    @Published var errorMessage: String?
    @Published private(set) var statusMessage = "Tap to stop & save"

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioRecorder: AVAudioRecorder?
    private var audioURL: URL?
    private var startedAt: Date?
    private var timerTask: Task<Void, Never>?

    func start() async {
        guard !isRecording else { return }

        do {
            errorMessage = nil
            try await requestPermissions()
            try configureAudioSession()
            try startCapture()
        } catch {
            errorMessage = error.localizedDescription
            cleanup()
        }
    }

    func stop() async -> RecordingResult? {
        guard isRecording else { return nil }

        let finalURL = audioURL

        audioRecorder?.stop()
        timerTask?.cancel()
        isRecording = false
        statusMessage = "Finishing transcript..."

        let duration = elapsedSeconds
        guard let finalURL else {
            cleanup()
            return nil
        }

        let finalTranscript = await transcribe(url: finalURL).trimmingCharacters(in: .whitespacesAndNewlines)
        if finalTranscript.isEmpty && errorMessage == nil {
            errorMessage = "No transcript returned. The audio was saved."
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        audioRecorder = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        startedAt = nil
        audioURL = nil
        statusMessage = "Tap to stop & save"

        return RecordingResult(
            transcript: finalTranscript,
            audioURL: finalURL,
            durationSeconds: max(duration, 1)
        )
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        if speechStatus != .authorized {
            errorMessage = "Speech recognition permission is required to transcribe recordings. Audio will still be saved."
        }

        let micAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard micAllowed else {
            throw ForgeBuddyError.message("Microphone permission is required to record voice notes.")
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startCapture() throws {
        transcript = ""
        elapsedSeconds = 0
        levels = Array(repeating: 0.12, count: 34)
        statusMessage = "Tap to stop & save"

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeBuddy-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw ForgeBuddyError.message("Could not start microphone recording.")
        }

        audioRecorder = recorder
        audioURL = fileURL

        startedAt = Date()
        isRecording = true
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    guard let self, let startedAt = self.startedAt else { return }
                    self.elapsedSeconds = Date().timeIntervalSince(startedAt)
                    self.audioRecorder?.updateMeters()
                    let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -80
                    self.pushLevel(Self.level(fromPower: power))
                }
            }
        }
    }

    private func transcribe(url: URL) async -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            errorMessage = "Speech recognition permission is required to transcribe recordings. The audio was saved."
            return ""
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now. The audio was saved."
            return ""
        }

        statusMessage = "Transcribing..."

        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.taskHint = .dictation

            let lock = NSLock()
            var didResume = false
            var latestTranscript = ""

            func resumeOnce(_ text: String, message: String? = nil) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                lock.unlock()

                Task { @MainActor [weak self] in
                    self?.transcript = text
                    if let message {
                        self?.errorMessage = message
                    }
                }
                continuation.resume(returning: text)
            }

            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    lock.lock()
                    latestTranscript = text
                    lock.unlock()

                    Task { @MainActor [weak self] in
                        self?.transcript = text
                    }

                    if result.isFinal {
                        resumeOnce(text)
                    }
                }

                if let error {
                    lock.lock()
                    let text = latestTranscript
                    lock.unlock()
                    resumeOnce(text, message: text.isEmpty ? error.localizedDescription : nil)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                lock.lock()
                let text = latestTranscript
                lock.unlock()
                resumeOnce(text, message: text.isEmpty ? "Transcript timed out. The audio was saved." : nil)
            }
        }
    }

    private func cleanup() {
        audioRecorder?.stop()
        recognitionTask?.cancel()
        timerTask?.cancel()
        audioRecorder = nil
        audioURL = nil
        startedAt = nil
        isRecording = false
        elapsedSeconds = 0
    }

    private func pushLevel(_ value: CGFloat) {
        let clamped = min(max(value, 0.08), 1)
        levels.append(clamped)
        if levels.count > 34 {
            levels.removeFirst(levels.count - 34)
        }
    }

    private static func level(fromPower power: Float) -> CGFloat {
        guard power.isFinite else { return 0.08 }
        let normalized = max(0, min(1, (power + 55) / 55))
        return max(0.08, CGFloat(normalized))
    }
}
