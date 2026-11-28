import AVFoundation
import Foundation
import OSLog

/// Plays the server MP3. AVSpeech is a last-resort fallback only.
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = SpeechPlayer()

    /// Taps start audio on `audioQueue` so a tap never waits on the audio system, so these three
    /// are read and written from both queues. `stateLock` guards them.
    private let stateLock = NSLock()
    private var _audioPlayer: AVAudioPlayer?
    private var _streamPlayer: AVPlayer?
    private var _playbackToken = UUID()
    private var audioPlayer: AVAudioPlayer? {
        get { stateLock.withLock { _audioPlayer } }
        set { stateLock.withLock { _audioPlayer = newValue } }
    }
    private var streamPlayer: AVPlayer? {
        get { stateLock.withLock { _streamPlayer } }
        set { stateLock.withLock { _streamPlayer = newValue } }
    }
    private var playbackToken: UUID {
        get { stateLock.withLock { _playbackToken } }
        set { stateLock.withLock { _playbackToken = newValue } }
    }
    private let audioQueue = DispatchQueue(label: "com.davidgeorgehope.hopesvoice.audio", qos: .userInitiated)
    private var endObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private let sessionLock = NSLock()
    private var sessionReady = false

    /// Slugs of the last Speak request, in play order. Set before audio starts.
    private(set) var lastSpeakSequence: [String] = []
    /// Cached MP3 URLs requested for that sequence, same order.
    private(set) var lastSpeakAudioURLs: [URL] = []
    /// On-device voice used when spoken text differs from the cached MP3, or when there is no MP3.
    var voiceSettings: BoardImportVoice = .default

    func speak(card: Card, spokenText: String? = nil, cache: AssetCache, api: APIClient) {
        prepareSession()
        stop()
        lastSpeakSequence = [card.slug]
        lastSpeakAudioURLs = [cache.audioURL(for: card.slug)]
        if let spoken = Self.customSpeech(for: card, spokenText: spokenText) {
            SpeakTrace.log("speak utterance slug=\(card.slug) word=\(card.word) text=\(spoken)")
            speakFallback(spoken)
            return
        }
        SpeakTrace.log("speak slug=\(card.slug) word=\(card.word) audio=\(cache.audioURL(for: card.slug).path)")
        playNow(card: card, cache: cache, api: api)
    }

    /// Play each card's cached MP3 one after another. Does not concatenate a single phrase.
    /// When `spokenTexts` differs from the card word, that item uses AVSpeech instead of the MP3.
    func speakSequence(_ cards: [Card], spokenTexts: [String]? = nil, cache: AssetCache, api: APIClient) {
        prepareSession()
        stop()
        let token = playbackToken
        lastSpeakSequence = cards.map(\.slug)
        lastSpeakAudioURLs = cards.map { cache.audioURL(for: $0.slug) }
        SpeakTrace.log("speak-strip start count=\(cards.count) slugs=\(lastSpeakSequence.joined(separator: ","))")
        for (index, card) in cards.enumerated() {
            let audio = cache.audioURL(for: card.slug)
            SpeakTrace.log("speak-strip queue [\(index + 1)/\(cards.count)] slug=\(card.slug) word=\(card.word) audio=\(audio.path)")
        }
        Task { @MainActor in
            for (index, card) in cards.enumerated() {
                guard playbackToken == token else { return }
                let spoken = spokenTexts.flatMap { $0.indices.contains(index) ? Self.customSpeech(for: card, spokenText: $0[index]) : nil }
                if let spoken {
                    SpeakTrace.log("speak-strip utterance [\(index + 1)/\(cards.count)] slug=\(card.slug) text=\(spoken)")
                    speakFallback(spoken)
                    let wait = max(0.6, Double(spoken.count) * 0.07)
                    try? await Task.sleep(for: .seconds(wait))
                    continue
                }
                let audio = cache.audioURL(for: card.slug)
                SpeakTrace.log("speak-strip play [\(index + 1)/\(cards.count)] slug=\(card.slug) word=\(card.word) audio=\(audio.path)")
                await playAndWait(card: card, cache: cache, api: api, token: token)
            }
            if playbackToken == token {
                SpeakTrace.log("speak-strip done")
            }
        }
    }

    /// Spoken text that should replace the cached MP3. Nil means play the recording.
    static func customSpeech(for card: Card, spokenText: String?) -> String? {
        guard let spoken = spokenText?.trimmingCharacters(in: .whitespacesAndNewlines), !spoken.isEmpty else {
            return nil
        }
        if spoken.caseInsensitiveCompare(card.word) == .orderedSame {
            return nil
        }
        return spoken
    }

    func stop() {
        playbackToken = UUID()
        audioPlayer?.stop()
        audioPlayer = nil
        streamPlayer?.pause()
        streamPlayer = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        audioQueue.async { [synthesizer] in
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    private func playNow(card: Card, cache: AssetCache, api: APIClient) {
        let local = cache.audioURL(for: card.slug)
        if cache.hasAudio(card.slug) {
            let token = playbackToken
            let word = card.word
            let slug = card.slug
            // Creating and starting the player can wait on the audio system (hundreds of ms
            // right after launch). Do it off the main thread; the visual tap feedback is instant.
            audioQueue.async { [self] in
                do {
                    let player = try AVAudioPlayer(contentsOf: local)
                    player.delegate = self
                    player.prepareToPlay()
                    guard playbackToken == token else { return } // a newer tap or Stop replaced this one
                    audioPlayer = player
                    player.play()
                    if playbackToken != token { player.stop() }
                    SpeakTrace.log("speak cached mp3 slug=\(slug) audio=\(local.path)")
                } catch {
                    SpeakTrace.log("local mp3 failed, not fetching remote: \(error)")
                    speakFallback(word)
                }
            }
            return
        }

        if let remote = api.absoluteURL(for: card.audioURL) {
            let item = AVPlayerItem(url: remote)
            let player = AVPlayer(playerItem: item)
            player.play()
            streamPlayer = player
            SpeakTrace.log("speak remote stream slug=\(card.slug) url=\(remote.absoluteString)")
            return
        }

        speakFallback(card.word)
    }

    private func playAndWait(card: Card, cache: AssetCache, api: APIClient, token: UUID) async {
        let local = cache.audioURL(for: card.slug)
        if cache.hasAudio(card.slug) {
            do {
                let player = try AVAudioPlayer(contentsOf: local)
                player.delegate = self
                player.prepareToPlay()
                let duration = player.duration
                player.play()
                audioPlayer = player
                SpeakTrace.log("speak-strip cached mp3 slug=\(card.slug) audio=\(local.path)")
                let wait = duration > 0.05 ? duration : 0.3
                try? await Task.sleep(for: .seconds(wait))
                return
            } catch {
                SpeakTrace.log("local mp3 failed, not fetching remote: \(error)")
                speakFallback(card.word)
                try? await Task.sleep(for: .milliseconds(600))
                return
            }
        }

        if let remote = api.absoluteURL(for: card.audioURL) {
            let item = AVPlayerItem(url: remote)
            let player = AVPlayer(playerItem: item)
            let done = PlaybackDone()
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in done.flag = true }
            endObserver = observer
            streamPlayer = player
            player.play()
            let deadline = Date().addingTimeInterval(6)
            while !done.flag && Date() < deadline && playbackToken == token {
                try? await Task.sleep(for: .milliseconds(50))
            }
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
            return
        }

        speakFallback(card.word)
        try? await Task.sleep(for: .milliseconds(600))
    }

    private func speakFallback(_ word: String) {
        let settings = voiceSettings
        audioQueue.async { [self] in
            let utterance = AVSpeechUtterance(string: word)
            if let voice = AVSpeechSynthesisVoice(identifier: settings.voiceId) {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }
            let rate = max(0.1, min(settings.rate, 2.0))
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (0.92 * Float(rate))
            utterance.pitchMultiplier = Float(max(0.5, min(settings.pitch, 2.0))) * 1.05
            synthesizer.speak(utterance)
        }
    }

    /// Set up the audio session off the main thread. Called at launch, and again by any tap that
    /// finds the session not ready, so no tap ever waits for it: activating the session can take
    /// hundreds of milliseconds, and seconds on a simulator.
    func warmUp() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            activateSession()
        }
    }

    /// Never blocks. If the session is ready this is a no-op; otherwise setup continues in the
    /// background and this tap plays with whatever session is current.
    private func prepareSession() {
        // A plain read: taking `sessionLock` here would wait for a setup that is in progress.
        if !sessionReady { warmUp() }
    }

    private func activateSession() {
        guard sessionLock.try() else { return } // another setup is already running
        defer { sessionLock.unlock() }
        guard !sessionReady else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            sessionReady = true
        } catch {
            SpeakTrace.log("audio session failed: \(error)")
        }
    }
}

private final class PlaybackDone: @unchecked Sendable {
    var flag = false
}

enum SpeakTrace {
    private static let logger = Logger(subsystem: "com.davidgeorgehope.hopesvoice", category: "speak")
    /// File appends happen here, never on the main thread: a tap must not wait on disk.
    private static let fileQueue = DispatchQueue(label: "com.davidgeorgehope.hopesvoice.speaktrace", qos: .utility)

    static func log(_ message: String) {
        let line = "Hope's Voice: \(message)"
        logger.info("\(message, privacy: .public)")
        fileQueue.async {
            print(line)
            fflush(stdout)
            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let url = dir.appendingPathComponent("speak.log")
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
