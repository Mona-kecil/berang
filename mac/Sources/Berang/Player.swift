import AVFoundation
import AppKit
import Observation
import PhononTTS
import Speakable
import TextGrab
import UniformTypeIdentifiers

/// Reads the window the user was last in, highlighting the sentence and word being heard (Model/Player.tla).
@MainActor @Observable final class Player {
    enum State: Equatable {
        case idle, downloading, loading, recognizing, playing, paused
        case failed(Failure)

        var isFailed: Bool { if case .failed = self { true } else { false } }
    }

    /// Why a request failed, and the permission it lacks when that is the reason.
    struct Failure: Equatable {
        let message: String
        let permission: Permission?

        init(_ error: Error) {
            message = "\(error)"
            permission = switch error {
            case GrabError.notTrusted: .accessibility
            case ScreenAreaError.notAllowed, ScreenAreaError.drawnText: .screenRecording
            default: nil
            }
        }
    }

    /// A file opened or dropped onto Berang's window, ready to read once the user clicks Read
    /// (Model/Player.tla, StageOnDrop).
    struct StagedFile: Equatable {
        let url: URL
        let title: String
        let start: Int
        let total: Int
        let resumed: Bool

        var progress: Double { total > 0 ? min(max(Double(start) / Double(total), 0), 1) : 0 }
        var percent: Int { Int((progress * 100).rounded()) }
    }

    struct ReadingInfo: Equatable {
        let title: String
        let subtitle: String?
        let isFile: Bool
        let index: Int
        let total: Int

        var progress: Double { total > 0 ? min(max(Double(index) / Double(total), 0), 1) : 0 }
        var percent: Int { Int((progress * 100).rounded()) }
    }

    struct PreviewVoice: Equatable {
        let engine: Engine
        let name: String
    }

    struct DownloadFailure: Equatable {
        let engine: Engine
        let message: String
    }

    private(set) var state = State.idle {
        didSet { if (oldValue == .idle) != (state == .idle) { showing?(state != .idle) } }
    }
    /// Told whether the player shows, as the state leaves or returns to idle.
    @ObservationIgnored var showing: ((Bool) -> Void)?
    /// Told as a reading begins, and whether it reads an app's page, where text can be selected.
    @ObservationIgnored var began: ((_ app: Bool) -> Void)?
    static let speeds: ClosedRange<Float> = 0.5...3
    /// Kept across launches. Set within `speeds`, in steps of 0.1, through `step`.
    var speed: Float = Player.savedSpeed {
        didSet {
            audio.rate = speed
            UserDefaults.standard.set(speed, forKey: "speed")
        }
    }
    /// The voice's words per minute at 1×, from what it has read: words over seconds of voice, pauses included.
    private(set) var pace: Double?
    @ObservationIgnored private var paced = (voice: "", words: 0, seconds: 0.0)
    /// The block reading continued from, on a return to a page read before. Clears once two blocks have played.
    private(set) var resumedAt: Int?
    /// How much of the voice has downloaded, from 0 to 1, while it downloads.
    private(set) var download: Double?
    private(set) var downloadError: DownloadFailure?
    /// The engine and voice reading, one of the engine's `voices`. Kept across launches.
    private(set) var engine: Engine
    private(set) var voice: String
    /// The engine downloading, while `download` counts.
    private(set) var downloading: Engine?
    private(set) var previewing: PreviewVoice?
    /// Whether Berang has read anything yet, which ends setup's last step.
    private(set) var hasRead = UserDefaults.standard.bool(forKey: "hasRead") {
        didSet { UserDefaults.standard.set(hasRead, forKey: "hasRead") }
    }
    private(set) var stagingTitle: String?
    /// A dropped or chosen file waiting for explicit Read (Model/Player.tla, StageOnDrop).
    private(set) var staged: StagedFile?
    private(set) var fileError: String?
    private(set) var reading: ReadingInfo?
    private(set) var isReadingVoicesText = false

    @ObservationIgnored private let audio = AudioOut()
    @ObservationIgnored private let highlight = Highlight()
    /// A voice's recorded preview, playing.
    @ObservationIgnored private var clip: AVAudioPlayer?
    @ObservationIgnored private var clipDelegate: ClipDelegate?
    @ObservationIgnored private var clipGeneration = 0
    @ObservationIgnored private var speakingSample = false
    @ObservationIgnored private var tts: (any Speech)?
    /// The engine `tts` runs, which differs from `engine` after a voice of another engine is chosen.
    @ObservationIgnored private var ttsEngine: Engine?
    private var needsLoad: Bool { tts == nil || ttsEngine != engine }
    @ObservationIgnored private var page: Page?
    @ObservationIgnored private var stagedPage: Page?
    @ObservationIgnored private var stageTask: Task<Void, Never>?
    @ObservationIgnored private var stageGeneration = 0
    @ObservationIgnored private var activeMeta: (title: String, subtitle: String?, isFile: Bool)?
    /// The selection in the page being read when reading started or last moved to one, which the read shortcut
    /// leaves alone (Model/Jump.tla, Remember).
    @ObservationIgnored private var seenSelection: Selected?
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
    /// The request whose voice is loading, which a voice chosen meanwhile keeps waiting.
    @ObservationIgnored private var active: Source?
    /// The app to read: the last one active other than this one and System Settings. The panel never
    /// takes focus, so this is the app the user is looking at, even after granting Accessibility access.
    @ObservationIgnored private var target = NSWorkspace.shared.frontmostApplication

    /// Shown beside System Settings when a reading needs a permission that is off.
    let guide: PermissionGuide

    init(guide: PermissionGuide) {
        self.guide = guide
        let engine = Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? Engine.starting
        self.engine = engine
        voice = UserDefaults.standard.string(forKey: "voice") ?? engine.defaultVoice
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
        return speeds.contains(saved) ? step(saved) : 1
    }

    /// The nearest speed to `s` in steps of 0.1 within `speeds`.
    static func step(_ s: Float) -> Float {
        min(max((s * 10).rounded() / 10, speeds.lowerBound), speeds.upperBound)
    }

    static func supports(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if ext == "epub" { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .pdf) || type.conforms(to: .epub) || type.conforms(to: .image) || type.conforms(to: .plainText)
    }

    /// Changes the speed by `delta`, as the speed shortcuts do.
    func nudge(_ delta: Float) { speed = Self.step(speed + delta) }

    func playPause() {
        switch state {
        case .playing: audio.pause(); state = .paused
        case .paused: audio.resume(); state = .playing
        case .idle, .failed, .recognizing: open(.window)
        case .downloading, .loading: pending = .window
        }
    }

    /// The read shortcut. While reading, text newly selected in the page being read moves reading there; otherwise
    /// it pauses or resumes, like the player's button (Model/Jump.tla). Returns whether reading moved.
    @discardableResult func readOrPause() -> Bool {
        if state == .playing || state == .paused, let page, let selection = selected(in: page), selection != seenSelection {
            seenSelection = selection
            move(to: selection.block)
            return true
        }
        playPause()
        return false
    }

    func skip(_ delta: Int) {
        guard let page, state == .playing || state == .paused else { return }
        move(to: min(max(index + delta, 0), page.blocks.count - 1))
    }

    /// Plays on from block `b`.
    private func move(to b: Int) {
        index = b
        resumedAt = nil
        cancel()
        if state == .paused { audio.resume() }
        let g = generation
        task = Task { await read(g) }
    }

    /// Accessibility turned on, so a failure for lacking it no longer holds (Model/Permission.tla, ClearOnGrant).
    func accessibilityGranted() {
        if case .failed(let failure) = state, failure.permission == .accessibility { stop() }
    }

    /// The failure card's button. With Accessibility already on there is nothing to switch on, so the failure goes.
    func openSettings(for permission: Permission) {
        if permission == .accessibility, AXIsProcessTrusted() { accessibilityGranted() } else { guide.show(permission) }
    }

    func stop() {
        cancel()
        page = nil
        activeMeta = nil
        reading = nil
        isReadingVoicesText = false
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
        speakingSample = false
        endPreview()
        audio.stop()
        clock?.invalidate()
        clock = nil
        highlight.hide()
    }

    func stopPreview() {
        endPreview()
        if speakingSample {
            speakingSample = false
            generation += 1
            task?.cancel()
            audio.stop()
        }
    }

    private func endPreview() {
        clipGeneration += 1
        clip?.stop()
        clip = nil
        clipDelegate = nil
        previewing = nil
    }

    private func playClip(at url: URL, engine: Engine, name: String) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        clipGeneration += 1
        let id = clipGeneration
        let delegate = ClipDelegate { [weak self] in
            Task { @MainActor in
                if self?.clipGeneration == id { self?.endPreview() }
            }
        }
        player.delegate = delegate
        clip = player
        clipDelegate = delegate
        guard player.play() else {
            endPreview()
            return false
        }
        previewing = PreviewVoice(engine: engine, name: name)
        return true
    }

    /// Reads the text in an area of the screen the user drags over, stopping what is playing.
    func readScreenArea() { open(.screenArea) }

    /// Stages a file without speaking until the user clicks Read (Model/Player.tla, StageOnDrop).
    func stageFile(_ url: URL) {
        stageGeneration += 1
        let sg = stageGeneration
        stageTask?.cancel()
        fileError = nil
        guard Self.supports(url) else {
            stagingTitle = nil
            staged = nil
            stagedPage = nil
            fileError = "Berang reads PDF, EPUB, images, and plain text."
            return
        }
        staged = nil
        stagedPage = nil
        stagingTitle = url.deletingPathExtension().lastPathComponent
        stageTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .userInitiated) { parseFile(url) }.value
            guard let self, self.stageGeneration == sg, !Task.isCancelled else { return }
            self.stagingTitle = nil
            guard let parsed else {
                self.fileError = "Berang can't read \(url.lastPathComponent)."
                return
            }
            let file = parsed.page()
            let saved = file.address.flatMap { self.positions[$0]?.index(in: file.blocks) }
            let resumed = saved != nil && saved != file.start
            let start = resumed ? saved! : file.start
            self.stagedPage = file
            self.staged = StagedFile(
                url: url,
                title: file.window,
                start: start,
                total: file.blocks.count,
                resumed: resumed
            )
        }
    }

    /// Starts reading the staged file, from its saved spot or from the start (Model/Player.tla, YouStartStaged).
    /// Keeps the staged file visible until playback begins so a failed voice load can be retried from Home.
    func readStaged(fromStart: Bool = false) {
        guard let staged, let file = stagedPage else { return }
        fileError = nil
        open(.stagedFile(url: staged.url, page: file, fromStart: fromStart))
    }

    /// Dismisses the staged file card without starting playback (Model/Player.tla, YouClearStaged).
    func clearStaged() {
        stageGeneration += 1
        stageTask?.cancel()
        stagingTitle = nil
        staged = nil
        stagedPage = nil
        fileError = nil
    }

    /// Reads text typed or pasted into the Voices window, to hear a voice on your own words.
    func readText(_ text: String) { open(.text(text)) }

    private enum Source { case window, screenArea, stagedFile(url: URL, page: Page, fromStart: Bool), text(String) }

    /// Starts a request, replacing whatever was playing or waiting. While the voice downloads or loads, the
    /// request waits for it instead (Model/Player.tla).
    private func open(_ source: Source) {
        if state == .downloading || state == .loading {
            pending = source
            return
        }
        stop()
        start(source)
    }

    /// Shows the guide to a permission the request needs and lacks, before the voice download.
    private func allow(_ source: Source) throws {
        switch source {
        case .window:
            guard AXIsProcessTrusted() else {
                guide.show(.accessibility)
                throw GrabError.notTrusted
            }
        case .screenArea:
            guard CGPreflightScreenCaptureAccess() else {
                askForScreenRecording()
                throw ScreenAreaError.notAllowed
            }
        case .stagedFile, .text: break
        }
    }

    /// Opens the guide the first time a reading needs Screen Recording. Afterwards the player's message offers it, so
    /// someone who said no isn't taken to System Settings at every press.
    private func askForScreenRecording() {
        guard !UserDefaults.standard.bool(forKey: "askedScreenRecording") else { return }
        UserDefaults.standard.set(true, forKey: "askedScreenRecording")
        guide.show(.screenRecording)
    }

    private func start(_ requested: Source) {
        let g = generation
        task = Task {
            do {
                try allow(requested)
                var source = requested
                if needsLoad {
                    active = requested
                    defer { if g == generation { active = nil } }
                    try await installVoice(generation: g)
                    guard g == generation else { return }
                    state = .loading
                    guard try await loadVoice(g) else { return }
                    if let latest = pending {
                        pending = nil
                        source = latest
                        try allow(source)
                    }
                }
                endPreview()
                var page: Page
                var resumes = false
                switch source {
                case .window:
                    guard let target else { throw PhononError(description: "Open a page to read, then press play.") }
                    page = try grab(target)
                    // An app that draws its own text, like a web reader drawing on a canvas, is read off the screen.
                    if page.blocks.isEmpty, let frame = page.viewportFrame {
                        guard CGPreflightScreenCaptureAccess() else {
                            askForScreenRecording()
                            throw ScreenAreaError.drawnText(app: page.app)
                        }
                        state = .recognizing  // Model/Player.tla, ShowRecognizing
                        page = page.with(try await readScreen(frame))
                        guard g == generation else { return }
                    }
                    guard !page.blocks.isEmpty else { throw PhononError(description: "\(page.app) shows no text to read.") }
                    pageKey = page.address ?? target.bundleIdentifier.map { "\($0) \(page.window)" }
                    resumes = page.startPoint == .screen && page.start == 0
                    let title = page.window.isEmpty ? page.app : page.window
                    activeMeta = (title: title, subtitle: page.window.isEmpty ? nil : page.app, isFile: false)
                    isReadingVoicesText = false
                case .screenArea:
                    state = .idle  // not loading while the user picks
                    guard let captured = try await captureScreenArea() else { return }
                    guard g == generation else {
                        try? FileManager.default.removeItem(at: captured)
                        return
                    }
                    endPreview()
                    state = .recognizing  // Model/Player.tla, ShowRecognizing
                    page = try await recognizeScreenArea(captured)
                    guard g == generation else { return }
                    pageKey = nil
                    activeMeta = (title: "Screen area", subtitle: nil, isFile: false)
                    isReadingVoicesText = false
                case .stagedFile(let url, let file, let fromStart):
                    page = file
                    pageKey = file.address
                    resumes = !fromStart
                    activeMeta = (title: file.window, subtitle: nil, isFile: true)
                    isReadingVoicesText = false
                    if staged?.url == url {
                        staged = nil
                        stagedPage = nil
                    }
                case .text(let text):
                    page = textPage(text)
                    guard !page.blocks.isEmpty else { throw PhononError(description: "Type something to read.") }
                    pageKey = nil
                    activeMeta = (title: "Sample text", subtitle: nil, isFile: false)
                    isReadingVoicesText = true
                }
                self.page = page
                seenSelection = selected(in: page)
                began?({ if case .window = source { true } else { false } }())
                index = page.start
                top = if case .stagedFile = source { page.start } else { 0 }
                // A file, or an unscrolled page with nothing selected, continues where the last reading stopped.
                if resumes, let pageKey, let saved = positions[pageKey]?.index(in: page.blocks), saved != page.start {
                    index = saved
                    resumedAt = saved
                }
                // A voice chosen since the engine loaded, from its recorded clip, applies from the first sentence.
                try await tts?.setVoice(voice)
                guard g == generation else { return }
                await read(g)
            } catch {
                guard g == generation, !(error is CancellationError) else { return }
                pending = nil
                isReadingVoicesText = false
                state = .failed(Failure(error))
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
        _ = playClip(at: url, engine: engine, name: name)
    }

    /// Downloads an engine ahead of reading, as setup and the Voices window offer, then reads with `voice`.
    func downloadVoice(_ engine: Engine, then voice: String? = nil) {
        guard !engine.isInstalled, state == .idle || state.isFailed else { return }
        cancel()
        if downloadError?.engine == engine { downloadError = nil }
        let g = generation
        task = Task {
            do {
                try await installVoice(engine, generation: g)
                guard g == generation else { return }
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
                guard g == generation, !(error is CancellationError) else { return }
                let hadPending = pending != nil
                pending = nil
                if hadPending {
                    state = .failed(Failure(error))
                } else {
                    downloadError = DownloadFailure(engine: engine, message: "\(error)")
                    state = .idle
                }
            }
        }
    }

    /// Chooses the voice to read with. While reading, the next sentence uses a voice of the same engine; a voice
    /// of another engine stops the reading. Otherwise the voice's recorded clip plays (Model/Player.tla).
    func choose(_ engine: Engine, _ name: String) {
        let switching = engine != self.engine
        self.engine = engine
        voice = name
        UserDefaults.standard.set(engine.rawValue, forKey: "engine")
        UserDefaults.standard.set(name, forKey: "voice")
        switch state {
        case .playing, .paused:
            if switching { audition() } else if let tts { Task { try? await tts.setVoice(name) } }
        case .downloading:
            preview(engine, name)  // beside the download, which then loads the chosen engine
        case .loading, .idle, .failed, .recognizing:
            audition()
        }
    }

    /// Plays the chosen voice's recorded clip at once and, if its engine isn't the loaded one, loads it behind the
    /// clip. A request waiting on a load keeps waiting, for this one. A voice with no clip speaks a sample instead,
    /// once its engine loads. Any other request replaces this.
    private func audition() {
        guard engine.isInstalled else { return }
        let waiting = state == .loading ? pending ?? active : nil
        stop()
        pending = waiting
        let playedClip = engine.preview(voice).map { playClip(at: $0, engine: engine, name: voice) } ?? false
        let speaks = !playedClip
        guard needsLoad || speaks else { return }
        let g = generation
        task = Task {
            do {
                if needsLoad {
                    state = .loading
                    guard try await loadVoice(g) else { return }
                    state = .idle
                    if let latest = pending {
                        pending = nil
                        start(latest)
                        return
                    }
                }
                guard speaks, let tts else { return }
                speakingSample = true
                defer { if g == generation { speakingSample = false } }
                for chunk in prepare(voiceSampleText) {
                    for try await part in tts.stream(chunk.text) {
                        try Task.checkCancellation()
                        _ = try audio.enqueue(part)
                    }
                }
            } catch {
                guard g == generation, !(error is CancellationError) else { return }
                pending = nil
                state = .failed(Failure(error))
            }
        }
    }

    /// Loads the chosen engine for request `g`, first letting go of the loaded one, and conditions it on the chosen
    /// voice, or on the engine's default when that voice is gone. Returns false, keeping nothing, if a later request
    /// replaced `g` meanwhile, such as a voice of another engine.
    private func loadVoice(_ g: Int) async throws -> Bool {
        let engine = self.engine
        tts = nil
        ttsEngine = nil
        let speech = try await engine.load()
        guard g == generation else { return false }
        let voices = engine.voices
        if !voices.contains(voice) { voice = voices.contains(engine.defaultVoice) ? engine.defaultVoice : voices.first ?? voice }
        try await speech.setVoice(voice)
        guard g == generation else { return false }
        tts = speech
        ttsEngine = engine
        return true
    }

    private func installVoice(_ engine: Engine? = nil, generation g: Int) async throws {
        let engine = engine ?? self.engine
        guard !engine.isInstalled else { return }
        state = .downloading
        downloading = engine
        download = 0
        defer {
            if g == generation {
                download = nil
                downloading = nil
            }
        }
        try await engine.install { [weak self] fraction in
            if self?.generation == g { self?.download = fraction }
        }
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
                    if !samples.isEmpty {
                        timeline.timeLast(samples, sampleRate: Engine.sampleRate)
                        measure(chunk.text, samples.count)
                    }
                }
            }
            try Task.checkCancellation()
            await audio.drain()
            try Task.checkCancellation()
        } catch {
            if g == generation, !(error is CancellationError) { state = .failed(Failure(error)) }
            return
        }
        guard g == generation else { return }
        // A page read to the end starts from the top next time.
        if let pageKey { positions[pageKey] = nil }
        stop()
    }

    private func measure(_ text: String, _ samples: Int) {
        let voice = "\(engine.rawValue)/\(self.voice)"
        if paced.voice != voice { paced = (voice, 0, 0) }
        paced.words += text.split(whereSeparator: \.isWhitespace).count
        paced.seconds += Double(samples) / Engine.sampleRate
        // A few words say little about a voice's pace.
        pace = paced.words >= 8 ? Double(paced.words) / paced.seconds * 60 : nil
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
        if let meta = activeMeta {
            reading = ReadingInfo(
                title: meta.title,
                subtitle: meta.subtitle,
                isFile: meta.isFile,
                index: b,
                total: page.blocks.count
            )
        }
        if let r = resumedAt, b >= r + 2 { resumedAt = nil }
        page.blocks[b].scrollToVisible()
    }
}

private final class ClipDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let finished: @Sendable () -> Void
    init(finished: @escaping @Sendable () -> Void) { self.finished = finished }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished() }
}

/// Five seconds of voice audio.
private let lookahead = Int(Engine.sampleRate) * 5
