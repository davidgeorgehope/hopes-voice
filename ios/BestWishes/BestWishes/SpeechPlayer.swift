import AVFoundation
import Foundation
import OSLog

/// Plays the server MP3. AVSpeech is a last-resort fallback only.
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = SpeechPlayer()

    private var audioPlayer: AVAudioPlayer?
    private var streamPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionReady = false
    private var playbackToken = UUID()

    /// Slugs of the last Speak request, in play order. Set before audio starts.
    private(set) var lastSpeakSequence: [String] = []
    /// Cached MP3 URLs requested for that sequence, same order.
    private(set) var lastSpeakAudioURLs: [URL] = []

    func speak(card: Card, cache: AssetCache, api: APIClient) {
        prepareSession()
        stop()
        lastSpeakSequence = [card.slug]
        lastSpeakAudioURLs = [cache.audioURL(for: card.slug)]
        SpeakTrace.log("speak slug=\(card.slug) word=\(card.word) audio=\(cache.audioURL(for: card.slug).path)")
        playNow(card: card, cache: cache, api: api)
    }

    /// Play each card's cached MP3 one after another. Does not concatenate a single phrase.
    func speakSequence(_ cards: [Card], cache: AssetCache, api: APIClient) {
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
                let audio = cache.audioURL(for: card.slug)
                SpeakTrace.log("speak-strip play [\(index + 1)/\(cards.count)] slug=\(card.slug) word=\(card.word) audio=\(audio.path)")
                await playAndWait(card: card, cache: cache, api: api, token: token)
            }
            if playbackToken == token {
                SpeakTrace.log("speak-strip done")
            }
        }
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
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func playNow(card: Card, cache: AssetCache, api: APIClient) {
        let local = cache.audioURL(for: card.slug)
        if cache.hasAudio(card.slug) {
            do {
                let player = try AVAudioPlayer(contentsOf: local)
                player.delegate = self
                player.prepareToPlay()
                player.play()
                audioPlayer = player
                SpeakTrace.log("speak cached mp3 slug=\(card.slug) audio=\(local.path)")
                return
            } catch {
                SpeakTrace.log("local mp3 failed, not fetching remote: \(error)")
                speakFallback(card.word)
                return
            }
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
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }

    private func prepareSession() {
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

    static func log(_ message: String) {
        let line = "Hope's Voice: \(message)"
        print(line)
        fflush(stdout)
        logger.info("\(message, privacy: .public)")
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
