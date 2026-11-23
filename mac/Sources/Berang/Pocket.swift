import Foundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioTTS

/// Pocket TTS 100M (CC-BY-4.0) from Kyutai, in its MLX version, run on the GPU.
enum PocketVoice {
    private static let repo = "mlx-community/pocket-tts"
    /// Where the model is kept: Berang's own folder, not the shared Hugging Face cache.
    private static let cache = HubCache(cacheDirectory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Berang/Pocket"))
    private static var folder: URL {
        cache.cacheDirectory.appending(path: "mlx-audio").appending(path: repo.replacingOccurrences(of: "/", with: "_"))
    }

    /// The download writes its listing of the model's files last, once every file is in, so a download cut short
    /// doesn't count (Model/Update.tla).
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".mlx-audio-snapshot.json").path)
    }

    /// The voices in the downloaded model, alba first, as it is the model's default.
    static var names: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "embeddings").path)) ?? []
        let names = files.filter { $0.hasSuffix(".safetensors") }.map { String($0.dropLast(".safetensors".count)) }.sorted()
        return names.contains("alba") ? ["alba"] + names.filter { $0 != "alba" } : names
    }

    static func install(progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let id = Repo.ID(rawValue: repo) else { return }
        var reported = -1
        _ = try await ModelUtils.resolveOrDownloadModel(
            client: HubClient(cache: cache), cache: cache, repoID: id, requiredExtension: "safetensors"
        ) { p in
            let percent = Int(p.fractionCompleted * 100)
            guard percent != reported else { return }
            reported = percent
            progress(Double(percent) / 100)
        }
        // The download leaves a Hugging Face cache beside the model folder it copies out, which is all `load` reads.
        let root = cache.cacheDirectory
        for item in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where item != "mlx-audio" {
            try? FileManager.default.removeItem(at: root.appending(path: item))
        }
    }

    static func load() async throws -> any Speech {
        // A cap on MLX's buffer cache saves about 200 MB for about 4% of speed (spikes/pocket-mlx).
        Memory.cacheLimit = 256 * 1024 * 1024
        let model = try await TTS.loadModel(modelRepo: folder.path)
        guard model.sampleRate == Int(Engine.sampleRate) else {
            throw PocketError(description: "Pocket speaks at \(model.sampleRate) Hz, not \(Int(Engine.sampleRate)).")
        }
        return PocketSpeech(model)
    }
}

struct PocketError: Error, CustomStringConvertible {
    let description: String
}

/// Pocket's model behind the player's Speech interface. One utterance runs at a time: a new one waits for the
/// one before it, even one that was cancelled, since MLX works on one stream of commands.
final class PocketSpeech: Speech, @unchecked Sendable {
    private let model: SpeechGenerationModel
    private let lock = NSLock()
    private var voice = "alba"
    private var last: Task<Void, Never>?

    init(_ model: SpeechGenerationModel) { self.model = model }

    /// Returns the GPU buffers MLX keeps for reuse once Pocket is let go, as when another engine is chosen.
    deinit { Memory.clearCache() }

    func setVoice(_ name: String) async throws {
        lock.withLock { voice = name }
    }

    func stream(_ text: String) -> AsyncThrowingStream<[Float], Error> {
        AsyncThrowingStream { continuation in
            let task = lock.withLock {
                let previous = last, voice = voice, model = model
                let task = Task {
                    await previous?.value
                    do {
                        for try await event in model.generateStream(
                            text: text, voice: voice, refAudio: nil, refText: nil, language: nil,
                            generationParameters: model.defaultGenerationParameters, streamingInterval: 0.08
                        ) {
                            try Task.checkCancellation()
                            if case .audio(let chunk) = event { continuation.yield(chunk.asArray(Float.self)) }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                last = task
                return task
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
