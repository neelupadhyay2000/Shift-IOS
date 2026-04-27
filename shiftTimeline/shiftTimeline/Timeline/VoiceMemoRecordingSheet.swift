import SwiftUI
import AVFoundation
import Models

// MARK: - Recording coordinator

@MainActor
@Observable
final class AudioRecordingCoordinator: NSObject, AVAudioRecorderDelegate {

    var isRecording = false
    var permissionDenied = false
    var recordingFailed = false
    var recordingStartDate: Date?
    var completedURL: URL?

    @ObservationIgnored private var recorder: AVAudioRecorder?

    func requestAndStart(for blockID: UUID) async {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { result in
                    continuation.resume(returning: result)
                }
            }
        }

        guard !Task.isCancelled else { return }

        guard granted else {
            permissionDenied = true
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)

            let url = Self.newFileURL(for: blockID)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            completedURL = url
            recordingStartDate = .now
            isRecording = true
        } catch {
            recordingFailed = true
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        recordingStartDate = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        isRecording = false
        recordingStartDate = nil
        completedURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func newFileURL(for blockID: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date.now.timeIntervalSince1970)
        return docs.appendingPathComponent("voicememo_\(blockID.uuidString)_\(timestamp).m4a")
    }

    // MARK: AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag { self.completedURL = nil }
            self.isRecording = false
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.completedURL = nil
            self.isRecording = false
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative, isActive: coordinator.isRecording)

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
        .alert(String(localized: "Microphone Access Required"), isPresented: $showPermissionAlert) {
            Button(String(localized: "Open Settings")) {
                if let url = URL(string: "app-settings:") {
                    openURL(url)
                }
                dismiss()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(String(localized: "SHIFT needs microphone access to record voice memos. Enable it in Settings."))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
