import AppKit
import TextGrab

enum ScreenAreaError: Error, CustomStringConvertible {
    case notAllowed, noText

    var description: String {
        switch self {
        case .notAllowed: "Screen Recording access is off for Berang. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .noText: "No text found in that area."
        }
    }
}

/// Asks for Screen Recording access the first time; macOS shows its prompt once.
func checkScreenAccess() throws {
    guard CGPreflightScreenCaptureAccess() else {
        CGRequestScreenCaptureAccess()
        throw ScreenAreaError.notAllowed
    }
}

/// Lets the user drag over part of the screen with the system's screenshot tool, and reads the text in it.
/// Nil when the user presses Escape.
@MainActor func pickScreenArea() async throws -> Page? {
    let url = FileManager.default.temporaryDirectory.appending(path: "berang-area.png")
    try? FileManager.default.removeItem(at: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let capture = Process()
    capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
    capture.arguments = ["-i", "-x", url.path]
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
        capture.terminationHandler = { _ in done.resume() }
        do { try capture.run() } catch { done.resume(throwing: error) }
    }
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let page = readScreenArea(url), !page.blocks.isEmpty else { throw ScreenAreaError.noText }
    return page
}
