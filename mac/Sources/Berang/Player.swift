import AVFoundation
import AppKit
import Observation
import PhononTTS
import Speakable
import TextGrab

/// Reads the window the user was last in, highlighting the sentence and word being heard.
@MainActor @Observable final class Player {
    enum State: Equatable {
        case idle, downloading, loading, playing, paused
        case failed(String)

        var isFailed: Bool { if case .failed = self { true } else { false } }
    }

    private(set) var state = State.idle
    /// Kept across launches.
    var speed: Float = Player.savedSpeed {
        didSet {
            audio.rate = speed
            UserDefaults.standard.set(speed, forKey: "speed")
        }
    }
    /// The block reading continued from, on a return to a page read before. Clears once two blocks have played.
    private(set) var resumedAt: Int?
    /// How much of the voice has downloaded, from 0 to 1, while it downloads.
    private(set) var download: Double?
    /// The engine and voice reading, one of the engine's `voices`. Kept across launches.
    private(set) var engine = Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .phonon
    private(set) var voice = UserDefaults.standard.string(forKey: "voice") ?? Engine.phonon.defaultVoice
    /// The engine downloading, while `download` counts.
    private(set) var downloading: Engine?
    /// Whether Berang has read anything yet, which ends setup's last step.
    private(set) var hasRead = UserDefaults.standard.bool(forKey: "hasRead") {
        didSet { UserDefaults.standard.set(hasRead, forKey: "hasRead") }
    }

    @ObservationIgnored private let audio = AudioOut()
    @ObservationIgnored private let highlight = Highlight()
    /// A voice's recorded preview, playing.
    @ObservationIgnored private var clip: AVAudioPlayer?
    @ObservationIgnored private var tts: (any Speech)?
    /// The engine `tts` runs, which differs from `engine` after a voice of another engine is chosen.
    @ObservationIgnored private var ttsEngine: Engine?
    private var needsLoad: Bool { tts == nil || ttsEngine != engine }
    @ObservationIgnored private var page: Page?
    /// The block being heard, or about to be.
    @ObservationIgnored private var index = 0
    /// What the queued audio says when, from the block reading started at.
    @ObservationIgnored private var timeline = Timeline()
    /// Follows the audio to move the highlight and the saved position.
    @ObservationIgnored private var clock: Timer?
    @ObservationIgnored private let positions = Positions()
    /// Where this page's reading position is kept.
    @ObservationIgnored private var pageKey: String?
    /// Where Start over goes: the top of a page, or where a book's text starts.
    @ObservationIgnored private var top = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Counts requests. Work begun for an older request stops at its next step without changing the player.
    @ObservationIgnored private var generation = 0
    /// What to read once the voice finishes downloading or loading: the latest request made meanwhile.
    @ObservationIgnored private var pending: Source?
    /// The app to read: the last one active other than this one and System Settings. The panel never
    /// takes focus, so this is the app the user is looking at, even after granting Accessibility access.
    @ObservationIgnored private var target = NSWorkspace.shared.frontmostApplication

    init() {
        audio.rate = speed
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                   app.bundleIdentifier != "com.apple.systempreferences" { self?.target = app }
            }
        }
    }

    private static var savedSpeed: Float {
        let saved = UserDefaults.standard.float(forKey: "speed")
        return (0.5...4).contains(saved) ? saved : 1
    }

    func playPause() {
        switch state {
        case .playing: audio.pause(); state = .paused
        case .paused: audio.resume(); state = .playing
        case .idle, .failed: open(.window)
        case .downloading, .loading: pending = .window
        }
    }

    func skip(_ delta: Int) {
        guard let page, state == .playing || state == .paused else { return }
        index = min(max(index + delta, 0), page.blocks.count - 1)
        resumedAt = nil
        cancel()
        if state == .paused { audio.resume() }
        let g = generation
        task = Task { await read(g) }
    }

    func stop() {
        cancel()
        page = nil
        resumedAt = nil
        state = .idle
    }

    func startOver() {
        guard page != nil else { return }
        index = top
        resumedAt = nil
        cancel()
        if state == .paused { audio.resume() }
        let g = generation
        task = Task { await read(g) }
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        endPreview()
        audio.stop()
        clock?.invalidate()
        clock = nil
        highlight.hide()
    }

    private func endPreview() {
        clip?.stop()
        clip = nil
    }

    /// Reads the text in an area of the screen the user drags over, stopping what is playing.
    func readScreenArea() { open(.screenArea) }

    /// Reads a PDF, EPUB, image, or text file, from where it was last left.
    func readFile(_ url: URL) { open(.file(url)) }

    private enum Source { case window, screenArea, file(URL) }

    /// Starts a request, replacing whatever was playing or waiting. While the voice downloads or loads, the
    /// request waits for it instead.
    private func open(_ source: Source) {
        if state == .downloading || state == .loading {
            pending = source
            return
        }
        stop()
        start(source)
    }

    /// Shows the system's permission prompt the first time, before the voice download.
    private func allow(_ source: Source) throws {
        switch source {
        case .window:
            guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            else { throw GrabError.notTrusted }
        case .screenArea: try checkScreenAccess()
        case .file: break
        }
    }

    private func start(_ requested: Source) {
        let g = generation
        task = Task {
            do {
                try allow(requested)
                var source = requested
                if needsLoad {
                    try await installVoice()
                    state = .loading
                    tts = try await loadVoice()
                    guard g == generation else { return }
                    if let latest = pending {
                        pending = nil
                        source = latest
                        try allow(source)
                    }
                }
                var page: Page
                switch source {
                case .window:
                    guard let target else { throw PhononError(description: "Open a page to read, then press play.") }
                    page = try grab(target)
                    // An app that draws its own text, like a web reader drawing on a canvas, is read off the screen.
                    if page.blocks.isEmpty, let frame = page.viewportFrame {
                        guard CGPreflightScreenCaptureAccess() else {
                            CGRequestScreenCaptureAccess()
                            throw ScreenAreaError.drawnText(app: page.app)
                        }
                        page = page.with(try await readScreen(frame))
                        guard g == generation else { return }
                    }
                    guard !page.blocks.isEmpty else { throw PhononError(description: "\(page.app) shows no text to read.") }
                    pageKey = page.address ?? target.bundleIdentifier.map { "\($0) \(page.window)" }
                case .screenArea:
                    state = .idle  // not loading while the user picks
                    let area = try await pickScreenArea()
                    guard g == generation, let area else { return }
                    page = area
                    pageKey = nil
                case .file(let url):
                    guard let file = readFilePage(url), !file.blocks.isEmpty
                    else { throw PhononError(description: "Berang can't read \(url.lastPathComponent).") }
                    page = file
                    pageKey = file.address
                }
                self.page = page
                index = page.start
                top = if case .file = source { page.start } else { 0 }
                // A file, or an unscrolled page with nothing selected, continues where the last reading stopped.
                let resumes = if case .file = source { true } else { page.startPoint == .screen && page.start == 0 }
                if resumes, let pageKey, let saved = positions[pageKey]?.index(in: page.blocks), saved != page.start {
                    index = saved
                    resumedAt = saved
                }
                await read(g)
            } catch {
                guard g == generation, !(error is CancellationError) else { return }
                pending = nil
                state = .failed("\(error)")
            }
        }
    }

    /// Plays a voice's recorded preview, which needs no download. While a voice downloads or loads it plays
    /// beside that; otherwise it replaces what was playing.
    func preview(_ engine: Engine, _ name: String) {
        guard let url = engine.preview(name) else { return }
        if state == .downloading || state == .loading {
            endPreview()
        } else {
            stop()
        }
        clip = try? AVAudioPlayer(contentsOf: url)
        clip?.play()
    }

    /// Downloads an engine ahead of reading, as setup and the Voices window offer, then reads with `voice`.
    func downloadVoice(_ engine: Engine, then voice: String? = nil) {
        guard !engine.isInstalled, state == .idle || state.isFailed else { return }
        task = Task {
            do {
                try await installVoice(engine)
                state = .idle
                if let voice, pending == nil {
                    choose(engine, voice)
                    return
                }
                if let latest = pending {
                    pending = nil
                    start(latest)
                }
            } catch {
                pending = nil
                state = .failed("\(error)")
            }
        }
    }

    /// Chooses the voice to read with. While reading, the next sentence uses a voice of the same engine; a voice
    /// of another engine, which must load first, stops the reading. Otherwise a sample plays in it.
    func choose(_ engine: Engine, _ name: String) {
        let switching = engine != self.engine
        self.engine = engine
        voice = name
        UserDefaults.standard.set(engine.rawValue, forKey: "engine")
        UserDefaults.standard.set(name, forKey: "voice")
        switch state {
        case .playing, .paused:
            if switching { sample() } else if let tts { Task { try? await tts.setVoice(name) } }
        case .downloading, .loading:
            break  // applied once the voice loads
        case .idle, .failed:
            sample()
        }
    }

    /// Plays a sentence in the chosen voice. Any request replaces it.
    private func sample() {
        guard engine.isInstalled else { return }
        stop()
        let g = generation
        task = Task {
            do {
                if needsLoad {
                    state = .loading
                    tts = try await loadVoice()
                    guard g == generation else { return }
                    state = .idle
                    if let latest = pending {
                        pending = nil
                        start(latest)
                        return
                    }
                }
                guard let tts else { return }
                endPreview()
                try await tts.setVoice(voice)
                for chunk in prepare(voiceSampleText) {
                    for try await part in tts.stream(chunk.text) {
                        try Task.checkCancellation()
                        _ = try audio.enqueue(part)
                    }
                }
            } catch {
                guard g == generation, !(error is CancellationError) else { return }
                state = .failed("\(error)")
            }
        }
    }

    /// Loads the chosen engine, first letting go of another one, and conditions it on the chosen voice, or on the
    /// engine's default when that voice is gone.
    private func loadVoice() async throws -> any Speech {
        tts = nil
        ttsEngine = nil
        let tts = try await engine.load()
        let voices = engine.voices
        if !voices.contains(voice) { voice = voices.contains(engine.defaultVoice) ? engine.defaultVoice : voices.first ?? voice }
        try await tts.setVoice(voice)
        ttsEngine = engine
        return tts
    }

    private func installVoice(_ engine: Engine? = nil) async throws {
        let engine = engine ?? self.engine
        guard !engine.isInstalled else { return }
        state = .downloading
        downloading = engine
        download = 0
        defer { download = nil; downloading = nil }
        try await engine.install { [weak self] in self?.download = $0 }
    }

    /// Plays from `index` to the end of the page, for request `g`. A skip cancels this task and starts another.
    private func read(_ g: Int) async {
        guard g == generation, let tts, let page else { return }
        endPreview()
        state = .playing
        hasRead = true
        timeline = Timeline()
        let first = index
        heard(first)
        clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        do {
            for b in first..<page.blocks.count {
                for chunk in prepare(page.blocks[b].text) {
                    // Synthesis runs ahead of playback by a few seconds, enough to play on without gaps.
                    while audio.queued > lookahead { try await Task.sleep(for: .milliseconds(100)) }
                    var samples: [Float] = []
                    for try await part in tts.stream(chunk.text) {
                        try Task.checkCancellation()
                        let start = try audio.enqueue(part)
                        if samples.isEmpty { timeline.append(block: b, chunk: chunk, start: start) }
                        samples += part
                    }
                    if !samples.isEmpty { timeline.timeLast(samples, sampleRate: Engine.sampleRate) }
                }
            }
            try Task.checkCancellation()
            await audio.drain()
            try Task.checkCancellation()
        } catch {
            if g == generation, !(error is CancellationError) { state = .failed("\(error)") }
            return
        }
        guard g == generation else { return }
        // A page read to the end starts from the top next time.
        if let pageKey { positions[pageKey] = nil }
        stop()
    }

    private func tick() {
        guard let page, let now = timeline.heard(at: audio.position) else { return }
        if now.block != index { heard(now.block) }
        highlight.show(page, block: now.block, sentence: now.chunk.source, word: now.word)
    }

    /// Called as block `b` starts to be heard.
    private func heard(_ b: Int) {
        guard let page else { return }
        index = b
        if let pageKey { positions[pageKey] = SavedPosition(page.blocks[b], at: b) }
        if let r = resumedAt, b >= r + 2 { resumedAt = nil }
        page.blocks[b].scrollToVisible()
    }
}

/// Five seconds of voice audio.
private let lookahead = Int(Engine.sampleRate) * 5
