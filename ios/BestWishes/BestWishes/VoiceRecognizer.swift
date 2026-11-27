import AVFoundation
import Foundation
import Observation
import Speech

/// Apple on-device speech → text. Never calls xAI/Grok. Kid mode must not start this.
@Observable
final class VoiceRecognizer {
    private(set) var isListening = false
    private(set) var partialTranscript = ""
    /// Set when a session ends with text. ContentView parses it, then clears.
    private(set) var finishedTranscript: String?
    private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var didInstallTap = false
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func clearFinishedTranscript() {
        finishedTranscript = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func toggle() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }

    func startListening() async {
        guard !isListening else { return }
        errorMessage = nil
        finishedTranscript = nil
        partialTranscript = ""

        guard recognizer != nil else {
            errorMessage = "Speech recognition is not available on this iPad."
            return
        }

        let speechOK = await requestSpeechAuthorization()
        guard speechOK else {
            errorMessage = "Allow speech recognition in Settings to add a word by voice."
            return
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else {
            errorMessage = "Allow the microphone in Settings to add a word by voice."
            return
        }

        do {
            try beginSession()
        } catch {
            errorMessage = error.localizedDescription
            tearDownEngine()
        }
    }

    func stopListening() {
        request?.endAudio()
        audioEngine?.stop()
        removeTapIfNeeded()
        isListening = false
        restorePlaybackSession()
        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        task = nil
        request = nil
        audioEngine = nil
        if !text.isEmpty {
            finishedTranscript = text
        }
    }

    /// Lock / disappear path. Drop any in-flight transcript so kid mode cannot confirm.
    func cancel() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine?.stop()
        removeTapIfNeeded()
        audioEngine = nil
        isListening = false
        partialTranscript = ""
        finishedTranscript = nil
        restorePlaybackSession()
    }

    private func beginSession() throws {
        let recognizer = try unwrapRecognizer()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceRecognizerError.noInput
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        didInstallTap = true

        engine.prepare()
        try engine.start()

        self.request = request
        self.audioEngine = engine
        self.isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finish(with: result.bestTranscription.formattedString)
                    }
                }
                if let error {
                    if self.isListening {
                        self.errorMessage = error.localizedDescription
                    }
                    self.finish(with: self.partialTranscript)
                }
            }
        }
    }

    private func finish(with transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        tearDownEngine()
        isListening = false
        restorePlaybackSession()
        if !text.isEmpty {
            finishedTranscript = text
        }
    }

    private func tearDownEngine() {
        audioEngine?.stop()
        removeTapIfNeeded()
        audioEngine = nil
    }

    private func removeTapIfNeeded() {
        guard didInstallTap else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        didInstallTap = false
    }

    private func restorePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func unwrapRecognizer() throws -> SFSpeechRecognizer {
        guard let recognizer else {
            throw VoiceRecognizerError.unavailable
        }
        return recognizer
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

enum VoiceRecognizerError: LocalizedError {
    case unavailable
    case noInput

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Speech recognition is not available on this iPad."
        case .noInput:
            return "This iPad has no microphone input for on-device speech."
        }
    }
}
