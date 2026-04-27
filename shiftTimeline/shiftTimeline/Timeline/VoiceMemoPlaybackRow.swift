import SwiftUI
import AVFoundation

// MARK: - Playback coordinator

@MainActor
@Observable
final class AudioPlaybackCoordinator: NSObject, AVAudioPlayerDelegate {

    var isPlaying = false
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var loadFailed = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?

    func load(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadFailed = true
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            loadFailed = true
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            stopProgressTimer()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            startProgressTimer()
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.currentTime = self.player?.currentTime ?? 0
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.player?.currentTime = 0
            self.stopProgressTimer()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - Row view

/// Playback control row shown in BlockInspector when a voice memo exists.
/// Automatically clears the block's memo reference if the file is missing on disk.
struct VoiceMemoPlaybackRow: View {

    let url: URL
    let onDelete: () -> Void

    @State private var playback = AudioPlaybackCoordinator()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                playback.isPlaying
                    ? String(localized: "Pause voice memo")
                    : String(localized: "Play voice memo")
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Voice Memo"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    if playback.isPlaying {
                        Text(formatDuration(playback.currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("of")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(formatDuration(playback.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Button(role: .destructive) {
                playback.stop()
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Delete voice memo"))
        }
        .onAppear {
            playback.load(url: url)
        }
        .onChange(of: playback.loadFailed) { _, failed in
            if failed { onDelete() }
        }
        .onDisappear {
            playback.stop()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
