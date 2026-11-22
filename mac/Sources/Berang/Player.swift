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
    }

    private(set) var state = State.idle
    var speed: Float = 1 { didSet { audio.rate = speed } }
    /// The block reading continued from, on a return to a page read before. Clears once two blocks have played.
    private(set) var resumedAt: Int?

    @ObservationIgnored private let audio = AudioOut()
    @ObservationIgnored private let highlight = Highlight()
    @ObservationIgnored private var tts: Phonon?
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
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The app to read: the last one active other than this one and System Settings. The panel never
    /// takes focus, so this is the app the user is looking at, even after granting Accessibility access.
    @ObservationIgnored private var target = NSWorkspace.shared.frontmostApplication

    init() {
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

    func playPause() {
        switch state {
        case .playing: audio.pause(); state = .paused
        case .paused: audio.resume(); state = .playing
        case .idle, .failed: start()
        case .downloading, .loading: break
        }
    }

    func skip(_ delta: Int) {
        guard let page, state == .playing || state == .paused else { return }
        index = min(max(index + delta, 0), page.blocks.count - 1)
        resumedAt = nil
        cancel()
        if state == .paused { audio.resume() }
        task = Task { await read() }
    }

    func stop() {
        cancel()
        page = nil
        resumedAt = nil
        state = .idle
    }

    func startOver() {
        guard page != nil else { return }
        index = 0
        resumedAt = nil
        cancel()
        if state == .paused { audio.resume() }
        task = Task { await read() }
    }

    private func cancel() {
        task?.cancel()
        audio.stop()
        clock?.invalidate()
        clock = nil
        highlight.hide()
    }

    private func start() {
        task = Task {
            do {
                // Shows the system's Accessibility prompt the first time, before the voice download.
                guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                else { throw GrabError.notTrusted }
                if tts == nil {
                    if !Voice.isInstalled {
                        state = .downloading
                        try await Voice.install()
                    }
                    state = .loading
                    tts = try await Voice.load()
                }
                guard let target else { throw PhononError(description: "Open a page to read, then press play.") }
                let page = try grab(target)
                guard !page.blocks.isEmpty else { throw PhononError(description: "\(page.app) shows no text to read.") }
                self.page = page
                pageKey = page.address ?? target.bundleIdentifier.map { "\($0) \(page.window)" }
                index = page.start
                // An unscrolled page with nothing selected continues where the last reading stopped.
                if page.startPoint == .screen, page.start == 0, let pageKey,
                   let saved = positions[pageKey]?.index(in: page.blocks), saved > 0 {
                    index = saved
                    resumedAt = saved
                }
                await read()
            } catch {
                state = .failed("\(error)")
            }
        }
    }

    /// Plays from `index` to the end of the page. A skip cancels this task and starts another.
    private func read() async {
        guard let tts, let page else { return }
        state = .playing
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
                    if !samples.isEmpty { timeline.timeLast(samples, sampleRate: Phonon.sampleRate) }
                }
            }
            try Task.checkCancellation()
            await audio.drain()
            try Task.checkCancellation()
        } catch {
            if !Task.isCancelled, !(error is CancellationError) { state = .failed("\(error)") }
            return
        }
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
private let lookahead = Int(Phonon.sampleRate) * 5
