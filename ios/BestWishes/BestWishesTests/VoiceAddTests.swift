import XCTest
@testable import BestWishes

@MainActor
final class VoiceAddTests: XCTestCase {
    func testAddPrefixExtractsTheWord() {
        XCTAssertEqual(VoiceAdd.word(from: "add juice"), "juice")
        XCTAssertEqual(VoiceAdd.word(from: "add bananas"), "bananas")
        XCTAssertEqual(VoiceAdd.word(from: "Add juice"), "juice")
        XCTAssertEqual(VoiceAdd.word(from: "ADD JUICE"), "JUICE")
        XCTAssertEqual(VoiceAdd.word(from: "  add   juice  "), "juice")
        XCTAssertEqual(VoiceAdd.word(from: "add juice."), "juice")
    }

    func testAddWordPrefixWinsOverAdd() {
        XCTAssertEqual(VoiceAdd.word(from: "add word juice"), "juice")
        XCTAssertEqual(VoiceAdd.word(from: "Add word juice"), "juice")
        XCTAssertEqual(VoiceAdd.word(from: "ADD WORD JUICE"), "JUICE")
        XCTAssertEqual(VoiceAdd.word(from: "  add  word   juice  "), "juice")
        XCTAssertNotEqual(VoiceAdd.word(from: "add word juice"), "word juice")
        XCTAssertEqual(VoiceAdd.word(from: "add bananas"), "bananas")
    }

    func testNewCardForExtractsThePhrase() {
        XCTAssertEqual(VoiceAdd.word(from: "new card for ice cream"), "ice cream")
        XCTAssertEqual(VoiceAdd.word(from: "New card for ice cream"), "ice cream")
        XCTAssertEqual(VoiceAdd.word(from: "new card for X"), "X")
        XCTAssertEqual(VoiceAdd.word(from: "new card for Apple Pie"), "Apple Pie")
    }

    func testBareWordIsTheWord() {
        XCTAssertEqual(VoiceAdd.word(from: "juice"), "juice")
        XCTAssertEqual(VoiceAdd.word(from: "bananas"), "bananas")
        XCTAssertEqual(VoiceAdd.word(from: "ice cream"), "ice cream")
        XCTAssertEqual(VoiceAdd.word(from: "  Daddy  "), "Daddy")
    }

    func testEmptyAndWhitespaceDoNotYieldACard() {
        XCTAssertNil(VoiceAdd.word(from: ""))
        XCTAssertNil(VoiceAdd.word(from: "   "))
        XCTAssertNil(VoiceAdd.word(from: "\n\t"))
        XCTAssertNil(VoiceAdd.word(from: "add"))
        XCTAssertNil(VoiceAdd.word(from: "add "))
        XCTAssertNil(VoiceAdd.word(from: "add word"))
        XCTAssertNil(VoiceAdd.word(from: "add word "))
        XCTAssertNil(VoiceAdd.word(from: "new card for"))
        XCTAssertNil(VoiceAdd.word(from: "new card for "))
        XCTAssertNil(VoiceAdd.word(from: "..."))
    }

    func testKidChromeHidesMicAndCaregiverChromeShowsIt() {
        let suiteName = "bw-voice-chrome-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mode = CaregiverMode(defaults: defaults)
        XCTAssertFalse(mode.isCaregiver)
        XCTAssertFalse(mode.showsVoiceChrome)
        XCTAssertFalse(mode.showsAddChrome)

        mode.unlock()
        XCTAssertTrue(mode.showsVoiceChrome)
        XCTAssertTrue(mode.showsAddChrome)

        mode.lock()
        XCTAssertFalse(mode.showsVoiceChrome)
        XCTAssertFalse(mode.showsAddChrome)

        mode.applyLaunchArguments(["-CaregiverMode"])
        XCTAssertTrue(mode.showsVoiceChrome)

        mode.applyLaunchArguments(["-KidMode"])
        XCTAssertFalse(mode.showsVoiceChrome)
    }

    func testBoardUIGatesMicOnCaregiverFlag() throws {
        let content = try source("BestWishes/ContentView.swift")
        XCTAssertTrue(content.contains("mode.showsVoiceChrome"))
        XCTAssertTrue(content.contains("accessibilityIdentifier(\"voiceAddMic\")"))
        XCTAssertTrue(content.contains("VoiceAdd.word(from:"))
        XCTAssertTrue(content.contains("VoiceAdd.confirm"))
        XCTAssertTrue(content.contains("VoiceConfirmSheet"))
        XCTAssertTrue(content.contains("word: voiceConfirmWord"))
        XCTAssertTrue(content.contains("\"-VoiceTranscript\""))
        XCTAssertTrue(content.contains("if mode.showsVoiceChrome"))
        XCTAssertFalse(content.contains("SFSpeechAudioBufferRecognitionRequest()"))
        XCTAssertEqual(content.components(separatedBy: "VoiceAdd.confirm").count - 1, 1)
        XCTAssertTrue(content.contains("onCancel: { pendingVoiceWord = nil }"))
        XCTAssertFalse(content.contains("onCancel: { pendingVoiceWord = nil; Task { await VoiceAdd.confirm"))
    }

    func testConfirmSheetUsesEditableTextFieldBinding() throws {
        let sheet = try source("BestWishes/VoiceAdd.swift")
        XCTAssertTrue(sheet.contains("@Binding var word: String"))
        XCTAssertTrue(sheet.contains("TextField(\"word\", text: $word)"))
        XCTAssertTrue(sheet.contains("accessibilityIdentifier(\"voiceConfirmWord\")"))
        XCTAssertTrue(sheet.contains("accessibilityIdentifier(\"voiceConfirmAdd\")"))
        XCTAssertTrue(sheet.contains("accessibilityIdentifier(\"voiceConfirmCancel\")"))
        XCTAssertTrue(sheet.contains("store.addWord"))
        XCTAssertFalse(sheet.contains("Text(\"“\\(word)”\")"))

        let content = try source("BestWishes/ContentView.swift")
        XCTAssertTrue(content.contains("word: voiceConfirmWord"))
        XCTAssertTrue(content.contains("let word = pendingVoiceWord"))
        XCTAssertTrue(content.contains("Task { await VoiceAdd.confirm(word, into: store) }"))
        let consume = Self.functionBody(named: "consumeVoiceTranscript", in: content)
        XCTAssertFalse(consume.contains("VoiceAdd.confirm"))
        XCTAssertFalse(consume.contains("store.addWord"))
        XCTAssertTrue(consume.contains("pendingVoiceWord = word"))
        let hooks = Self.functionBody(named: "runVoiceTranscriptLaunchHooks", in: content)
        XCTAssertFalse(hooks.contains("VoiceAdd.confirm"))
        XCTAssertFalse(hooks.contains("store.addWord"))
    }

    func testSpeechIsOnDeviceAndAppDoesNotCallXAI() throws {
        let recognizer = try source("BestWishes/VoiceRecognizer.swift")
        XCTAssertTrue(recognizer.contains("import Speech"))
        XCTAssertTrue(recognizer.contains("requiresOnDeviceRecognition"))
        XCTAssertTrue(recognizer.contains("requiresOnDeviceRecognition = true"))
        XCTAssertFalse(recognizer.contains("api.x.ai"))
        XCTAssertFalse(recognizer.contains("openai.com"))
        XCTAssertFalse(recognizer.contains("api.grok"))

        let parser = try source("BestWishes/VoiceAdd.swift")
        XCTAssertFalse(parser.contains("import Speech"))
        XCTAssertTrue(parser.contains("store.addWord"))
        XCTAssertTrue(parser.contains("accessibilityIdentifier(\"voiceConfirmSheet\")"))

        let pbx = try projectFile()
        XCTAssertTrue(pbx.contains("INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"))
        XCTAssertTrue(pbx.contains("INFOPLIST_KEY_NSMicrophoneUsageDescription"))
        XCTAssertTrue(pbx.contains("Speech.framework"))

        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BestWishes")
        let files = try FileManager.default.contentsOfDirectory(at: appRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("api.x.ai"), file.lastPathComponent)
            XCTAssertFalse(text.contains("api.openai.com"), file.lastPathComponent)
            XCTAssertFalse(text.contains("generativelanguage.googleapis.com"), file.lastPathComponent)
        }
    }

    func testConfirmParsedWordInsideFolderPostsFolderId() async throws {
        FixtureURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            FixtureURLProtocol.reset()
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-voice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let api = APIClient(baseURL: URL(string: "https://bestwishes.test")!, session: session)
        let store = CardStore(api: api, cache: AssetCache(root: root), player: SpeechPlayer())

        FixtureURLProtocol.handler = BoardContractTests.standardBoardHandler(extraFood: [BoardContractTests.applePieItem])
        await store.refresh()
        store.openFolder(id: "food")
        FixtureURLProtocol.recorded = []

        let word = VoiceAdd.word(from: "add Apple Pie")
        XCTAssertEqual(word, "Apple Pie")
        await VoiceAdd.confirm(try XCTUnwrap(word), into: store)

        let posts = FixtureURLProtocol.recorded.filter { $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards" }
        XCTAssertEqual(posts.count, 1)
        let body = BoardContractTests.json(posts[0].body)
        XCTAssertEqual(body["word"] as? String, word)
        XCTAssertEqual(body["folder_id"] as? String, "food")
        XCTAssertTrue(store.currentWordSlugs.contains("apple-pie"))
    }

    func testConfirmBareWordAtRootOmitsFolderId() async throws {
        FixtureURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            FixtureURLProtocol.reset()
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-voice-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let api = APIClient(baseURL: URL(string: "https://bestwishes.test")!, session: session)
        let store = CardStore(api: api, cache: AssetCache(root: root), player: SpeechPlayer())

        FixtureURLProtocol.handler = BoardContractTests.standardBoardHandler()
        await store.refresh()
        XCTAssertTrue(store.isAtRoot)
        FixtureURLProtocol.recorded = []
        FixtureURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            if method == "POST", path == "/v1/cards" {
                return (200, Data("""
                {
                  "word": "juice",
                  "slug": "juice",
                  "image_url": "/assets/juice/image.png",
                  "audio_url": "/assets/juice/audio.mp3",
                  "kind": "word",
                  "folder_id": null
                }
                """.utf8))
            }
            return try BoardContractTests.standardBoardHandler()(request)
        }

        let word = VoiceAdd.word(from: "juice")
        XCTAssertEqual(word, "juice")
        await VoiceAdd.confirm(try XCTUnwrap(word), into: store)

        let posts = FixtureURLProtocol.recorded.filter { $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards" }
        XCTAssertEqual(posts.count, 1)
        let body = BoardContractTests.json(posts[0].body)
        XCTAssertEqual(body["word"] as? String, "juice")
        XCTAssertNil(body["folder_id"])
    }

    func testConfirmEditedWordPostsTheEditedStringNotTheParse() async throws {
        FixtureURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            FixtureURLProtocol.reset()
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bw-voice-edit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let api = APIClient(baseURL: URL(string: "https://bestwishes.test")!, session: session)
        let store = CardStore(api: api, cache: AssetCache(root: root), player: SpeechPlayer())

        FixtureURLProtocol.handler = BoardContractTests.standardBoardHandler()
        await store.refresh()
        XCTAssertTrue(store.isAtRoot)
        FixtureURLProtocol.recorded = []
        FixtureURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            if method == "POST", path == "/v1/cards" {
                return (200, Data("""
                {
                  "word": "mango",
                  "slug": "mango",
                  "image_url": "/assets/mango/image.png",
                  "audio_url": "/assets/mango/audio.mp3",
                  "kind": "word",
                  "folder_id": null
                }
                """.utf8))
            }
            return try BoardContractTests.standardBoardHandler()(request)
        }

        let parsed = VoiceAdd.word(from: "add bananas")
        XCTAssertEqual(parsed, "bananas")
        let postsBeforeConfirm = FixtureURLProtocol.recorded.filter { $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards" }
        XCTAssertTrue(postsBeforeConfirm.isEmpty, "parse must not POST; confirm sheet Add posts the edited word")

        let edited = "mango"
        XCTAssertNotEqual(edited, parsed)
        await VoiceAdd.confirm(edited, into: store)

        let posts = FixtureURLProtocol.recorded.filter { $0.request.httpMethod == "POST" && $0.request.url?.path == "/v1/cards" }
        XCTAssertEqual(posts.count, 1)
        let body = BoardContractTests.json(posts[0].body)
        XCTAssertEqual(body["word"] as? String, edited)
        XCTAssertNotEqual(body["word"] as? String, parsed)
        XCTAssertNil(body["folder_id"])
    }

    private func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func projectFile() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BestWishes.xcodeproj/project.pbxproj")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func functionBody(named name: String, in source: String) -> String {
        guard let nameRange = source.range(of: "func \(name)") else { return "" }
        let fromName = source[nameRange.lowerBound...]
        guard let open = fromName.firstIndex(of: "{") else { return "" }
        var depth = 0
        var end = open
        for idx in fromName[open...].indices {
            let ch = fromName[idx]
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1 }
            end = idx
            if depth == 0 { break }
        }
        return String(fromName[open...end])
    }
}
