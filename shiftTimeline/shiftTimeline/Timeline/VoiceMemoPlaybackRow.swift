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
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

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
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            registerInterruptionObserver()
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        player?.prepareToPlay()
        isPlaying = false
        currentTime = 0
        unregisterInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Refreshes `currentTime` from the underlying player. Driven by a
    /// `TimelineView` in the row so we don't need a `Timer` (which would
    /// require runtime MainActor assumptions under strict concurrency).
    func refreshCurrentTime() {
        guard isPlaying, let player else { return }
        currentTime = player.currentTime
    }

    // MARK: Interruptions

    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw),
                type == .began
            else { return }
            Task { @MainActor [weak self] in
                self?.pauseForInterruption()
            }
        }
    }

    private func unregisterInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    private func pauseForInterruption() {
        player?.pause()
        isPlaying = false
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.player?.currentTime = 0
            // Re-arm so the next play call doesn't stall.
            self.player?.prepareToPlay()
            self.unregisterInterruptionObserver()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - Row view

/// Playback control row shown in BlockInspector when a voice memo exists.
///
/// If the file is missing on disk (e.g. CloudKit-synced record whose audio
/// has not been transferred to this device) the row shows an unavailable
/// state but does **not** clear the model field — the file may still arrive
/// later, or be present on another device.
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
                    .foregroundStyle(playback.loadFailed ? Color.gray : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(playback.loadFailed)
            .accessibilityLabel(
                playback.isPlaying
                    ? String(localized: "Pause voice memo")
                    : String(localized: "Play voice memo")
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Voice Memo"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if playback.loadFailed {
                    Text(String(localized: "Audio unavailable on this device"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        if playback.isPlaying {
                            Text(formatDuration(playback.currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(String(localized: "of"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(formatDuration(playback.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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
        .task(id: playback.isPlaying) {
            // Polls AVAudioPlayer for the current playback position while
            // playing; cancelled automatically when isPlaying flips or the
            // view disappears.
            while !Task.isCancelled, playback.isPlaying {
                playback.refreshCurrentTime()
                try? await Task.sleep(for: .milliseconds(250))
            }
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
