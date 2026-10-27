import Combine
import AVFoundation
import Foundation

// MARK: – VoiceCaptureService

/// Handles AVAudioRecorder lifecycle. Consumers observe `isRecording` and call
/// `stopAndTranscribe()` to get the audio URL for Whisper.

@MainActor
final class VoiceCaptureService: NSObject, ObservableObject {
    static let shared = VoiceCaptureService()

    @Published var isRecording = false
    @Published var audioLevel: Float = 0     // 0–1, for waveform UI

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var currentURL: URL?

    private override init() { super.init() }

    // ─────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────

    func startRecording() async throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:          16000,
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()
        isRecording = true

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.updateLevel() }
        }
    }

    /// Stops recording and returns the audio file URL.
    func stopRecording() -> URL? {
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        audioLevel = 0
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        return currentURL
    }

    // ─────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────

    private func updateLevel() {
        recorder?.updateMeters()
        let db = recorder?.averagePower(forChannel: 0) ?? -80
        // Map dBFS (-80…0) to 0…1
        audioLevel = max(0, min(1, (db + 80) / 80))
    }
}
