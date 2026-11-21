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

    /// Downloads the model bundle, checks it against the pinned digest, and installs it.
    static func install() async throws {
        let (zip, _) = try await URLSession.shared.download(from: release.appending(path: archive))
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
