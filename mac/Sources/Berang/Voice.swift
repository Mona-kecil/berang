import CryptoKit
import Foundation
import PhononTTS

/// Phonon 31m (Apache-2.0), fetched from the Phonon GitHub release on first use.
enum Voice {
    private static let release = URL(string: "https://github.com/gradium-ai/xn-ptts/releases/download/v0.7.1/")!
    private static let archive = "phonon-31m-en-coreml.zip"
    /// The release's SHA256SUMS leaves out the model archive, so the digest GitHub records for it is pinned here.
    private static let sha256 = "058cde756a5e67bcdb986e7c45fe431d41a1a9073e68aabae314c80631a34b76"

    static var isInstalled: Bool { PhononModels.isInstalled() }
    /// The download's size, for showing progress.
    static let downloadSize: Int64 = 137_000_000

    /// Downloads the model bundle, checks it against the pinned digest, and installs it. `progress` gets the
    /// fraction downloaded, in steps of a hundredth, on the main actor.
    static func install(progress: @escaping @MainActor (Double) -> Void) async throws {
        let watcher = DownloadProgress(progress)
        let (zip, _) = try await URLSession.shared.download(from: release.appending(path: archive), delegate: watcher)
        defer { try? FileManager.default.removeItem(at: zip) }
        let got = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard got == sha256 else { throw PhononError(description: "The voice download is corrupt. Try again.") }

        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await run("/usr/bin/ditto", "-x", "-k", zip.path, dir.path)
        let folders = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        guard let bundle = folders.first(where: { FileManager.default.fileExists(atPath: $0.appending(path: "bundle.json").path) })
        else { throw PhononError(description: "The voice download has no model bundle.") }
        try PhononModels.install(bundled: bundle)
    }

    static func load() async throws -> Phonon {
        try await Phonon.load(models: PhononModels.defaultDirectory, language: .english)
    }

    private static func run(_ tool: String, _ args: String...) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let status: Int32 = try await withCheckedThrowingContinuation { done in
            p.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { done.resume(throwing: error) }
        }
        guard status == 0 else { throw PhononError(description: "\(tool) failed with status \(status).") }
    }
}

/// Reports a download's progress from its task's Progress.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @MainActor (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var reported = -1

    init(_ report: @escaping @MainActor (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let percent = Int(progress.fractionCompleted * 100)
            guard percent != self.reported else { return }
            self.reported = percent
            let report = self.report
            Task { @MainActor in report(Double(percent) / 100) }
        }
    }
}
