import SwiftUI
import AVFoundation
import Models

// MARK: - Recording coordinator

@MainActor
@Observable
final class AudioRecordingCoordinator: NSObject, AVAudioRecorderDelegate {

    /// Hard cap to prevent runaway recordings from filling storage / CloudKit.
    static let maxRecordingDuration: TimeInterval = 5 * 60

    var isRecording = false
    var permissionDenied = false
    var recordingFailed = false
    var recordingStartDate: Date?
    var completedURL: URL?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    func requestAndStart(for blockID: UUID) async {
        let granted = await AVAudioApplication.requestRecordPermission()

        guard !Task.isCancelled else { return }

        guard granted else {
            permissionDenied = true
            return
        }

        guard let url = VoiceMemoStorage.makeRecordingURL(for: blockID) else {
            recordingFailed = true
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            // Speech-quality mono — keeps file size reasonable for sync.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            let started = newRecorder.record(forDuration: Self.maxRecordingDuration)
            guard started else {
                newRecorder.deleteRecording()
                recordingFailed = true
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            recorder = newRecorder
            completedURL = url
            recordingStartDate = .now
            isRecording = true
            registerInterruptionObserver()
        } catch {
            recordingFailed = true
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        recordingStartDate = nil
        unregisterInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        isRecording = false
        recordingStartDate = nil
        completedURL = nil
        unregisterInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
                self?.cancel()
            }
        }
    }

    private func unregisterInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    // MARK: AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag { self.completedURL = nil }
            self.isRecording = false
            self.recordingStartDate = nil
            self.unregisterInterruptionObserver()
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.completedURL = nil
            self.isRecording = false
            self.recordingFailed = true
            self.recordingStartDate = nil
            self.unregisterInterruptionObserver()
        }
    }
}

// MARK: - Sheet view

struct VoiceMemoRecordingSheet: View {

    let block: TimeBlockModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var coordinator = AudioRecordingCoordinator()
    @State private var showPermissionAlert = false
    @State private var showFailureAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, isActive: coordinator.isRecording)
                        .accessibilityHidden(true)

                    Text(block.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // Per-second elapsed counter via TimelineView — no Timer needed
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed: TimeInterval = coordinator.recordingStartDate
                        .map { context.date.timeIntervalSince($0) } ?? 0
                    Text(formatDuration(elapsed))
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(coordinator.isRecording ? .red : .secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel(String(localized: "Recording, \(Int(elapsed)) seconds"))
                        .accessibilityAddTraits(.updatesFrequently)
                }

                VStack(spacing: 8) {
                    Button {
                        coordinator.stopRecording()
                        if let url = coordinator.completedURL {
                            block.voiceMemoURL = url
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(coordinator.isRecording ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!coordinator.isRecording)
                    .accessibilityLabel(String(localized: "Stop recording"))

                    Text(String(localized: "Tap to stop"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .navigationTitle(String(localized: "Recording…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        coordinator.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            await coordinator.requestAndStart(for: block.id)
        }
        .onChange(of: coordinator.permissionDenied) { _, denied in
            if denied { showPermissionAlert = true }
        }
        .onChange(of: coordinator.recordingFailed) { _, failed in
            if failed { showFailureAlert = true }
        }
        .alert(String(localized: "Microphone Access Required"), isPresented: $showPermissionAlert) {
            Button(String(localized: "Open Settings")) {
                if let url = URL(string: "app-settings:") {
                    openURL(url)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(String(localized: "SHIFT needs microphone access to record voice memos. Enable it in Settings."))
        }
        .alert(String(localized: "Recording Unavailable"), isPresented: $showFailureAlert) {
            Button(String(localized: "OK"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(String(localized: "Voice memo recording could not start. Please try again."))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
