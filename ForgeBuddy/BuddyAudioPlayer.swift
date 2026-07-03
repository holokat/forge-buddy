import AVFoundation
import Foundation

@MainActor
final class BuddyAudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var currentURL: URL?
    private var endObserver: NSObjectProtocol?

    func toggle(url: URL) {
        if isPlaying && currentURL == url {
            pause()
        } else {
            play(url: url)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    private func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        if currentURL != url {
            removeEndObserver()
            player = AVPlayer(url: url)
            currentURL = url
            if let item = player?.currentItem {
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.isPlaying = false
                        self?.player?.seek(to: .zero)
                    }
                }
            }
        }

        player?.play()
        isPlaying = true
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}
