import AppKit
import TextGrab

enum ScreenAreaError: Error, CustomStringConvertible {
    case notAllowed, noText
    /// The app draws its text without telling the accessibility tree, and Berang may not record the screen to read it.
    case drawnText(app: String)

    static let turnOn = "Turn on Screen Recording for Berang in System Settings > Privacy & Security > Screen & System Audio Recording."

    var description: String {
        switch self {
        case .notAllowed: Self.turnOn
        case .noText: "No text found in that area."
        case .drawnText(let app): "\(app) draws its text as images. To read it, Berang recognizes the text on screen. \(Self.turnOn)"
        }
    }
}

/// Nil when the user presses Escape, or when the pick is cancelled, which closes the crosshair.
@MainActor func captureScreenArea() async throws -> URL? {
    let url = FileManager.default.temporaryDirectory.appending(path: "berang-area-\(UUID().uuidString).png")
    let capture = Process()
    capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
    capture.arguments = ["-i", "-x", url.path]
    let running = RunningProcess()
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            capture.terminationHandler = { _ in done.resume() }
            do {
                try capture.run()
                running.started(capture.processIdentifier)
            } catch {
                done.resume(throwing: error)
            }
        }
    } onCancel: {
        running.stop()
    }
    guard !Task.isCancelled, FileManager.default.fileExists(atPath: url.path) else {
        try? FileManager.default.removeItem(at: url)
        return nil
    }
    return url
}

/// Runs Vision text recognition on `url` off the main actor so the player's loading state stays responsive.
func recognizeScreenArea(_ url: URL) async throws -> Page {
    defer { try? FileManager.default.removeItem(at: url) }
    let paragraphs = await Task.detached(priority: .userInitiated) { recognizeImageBlocks(url) }.value
    guard let paragraphs, !paragraphs.isEmpty else { throw ScreenAreaError.noText }
    return screenAreaPage(paragraphs)
}

/// A child process that a cancelled task stops, even when the cancel comes before the process has started.
private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var stopped = false

    func started(_ id: pid_t) {
        let stopNow = lock.withLock { pid = id; return stopped }
        if stopNow { kill(id, SIGTERM) }
    }

    func stop() {
        let id = lock.withLock { stopped = true; return pid }
        if id > 0 { kill(id, SIGTERM) }
    }
}
