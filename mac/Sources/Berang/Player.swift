import AppKit
import Observation
import PhononTTS
import TextGrab

/// Reads the window the user was last in, one block at a time, highlighting each block as it plays.
@MainActor @Observable final class Player {
    enum State: Equatable {
        case idle, downloading, loading, playing, paused
        case failed(String)
    }

    private(set) var state = State.idle
    var speed: Float = 1 { didSet { audio.rate = speed } }

    @ObservationIgnored private let audio = AudioOut()
    @ObservationIgnored private let highlight = Highlight()
    @ObservationIgnored private var tts: Phonon?
    @ObservationIgnored private var page: Page?
    @ObservationIgnored private var index = 0
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
        cancel()
        if state == .paused { audio.resume() }
        task = Task { await read() }
    }

    func stop() {
        cancel()
        page = nil
        state = .idle
    }

    private func cancel() {
        task?.cancel()
        audio.stop()
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
                index = 0
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
        while index < page.blocks.count {
            let block = page.blocks[index]
            highlight.show(block, in: page)
            do {
                try await audio.play(tts.stream(speakable(block.text)))
            } catch {
                if !Task.isCancelled { state = .failed("\(error)") }
                return
            }
            index += 1
        }
        stop()
    }
}

/// Drops footnote markers such as "[12]" or "[a]", which every voice reads out.
private func speakable(_ text: String) -> String {
    text.replacing(/\[(?:\d+|[a-z]|citation needed)\]/, with: "")
}
