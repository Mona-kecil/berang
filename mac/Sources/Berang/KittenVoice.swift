import Foundation
import HuggingFace
import Kitten
import MLX
import MLXAudioTTS

/// Kitten TTS 2 nano (Apache-2.0) from KittenML, its English voices, run on the GPU through the Kitten target's
/// MLX port. English text becomes phonemes through Misaki's lexicons and a small BART for other words, as
/// mlx-audio-swift's MisakiTextProcessor does.
enum KittenVoice {
    private static let repo = URL(string: "https://huggingface.co/KittenML/kitten-tts-2-nano/resolve/main/")!
    private static let files: [(name: String, size: Int64)] = [
        ("config.json", 21_108), ("vocab.json", 1_313),
        ("kitten_tts_2_nano_en.safetensors", 67_859_256), ("voices_en.npz", 5_224_846),
    ]
    static let folder = Kitten2.defaultFolder
    /// Misaki's lexicons and BART, about 9 MB, from beshkenadze/kitten-tts-g2p (MIT).
    private static let lexicons = Kitten2.lexicons(in: folder)

    /// Each model file is moved in once it has fully arrived. The lexicons' download writes its listing of their
    /// files last, so lexicons cut short don't count (Model/Update.tla).
    static var isInstalled: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0.name).path) }
            && FileManager.default.fileExists(
                atPath: folder.appending(path: "G2P/mlx-audio/beshkenadze_kitten-tts-g2p/.mlx-audio-snapshot.json").path)
    }

    /// The English voices, from the model's config, without loading it.
    static var names: [String] {
        struct Listing: Decodable { let voices: [String: [Entry]]; struct Entry: Decodable { let key: String } }
        guard let data = try? Data(contentsOf: folder.appending(path: "config.json")),
              let listing = try? JSONDecoder().decode(Listing.self, from: data) else { return [] }
        return listing.voices["en"]?.map(\.key) ?? []
    }

    static func install(progress: @escaping @MainActor (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = Double(files.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        for file in files {
            let start = done
            let (download, response) = try await URLSession.shared.download(from: repo.appending(path: file.name))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw KittenError(description: "The Kitten download failed. Try again.")
            }
            let target = folder.appending(path: file.name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: download, to: target)
            done = start + file.size
            await progress(Double(done) / total * 0.9)
        }
        try await MisakiTextProcessor(cache: lexicons).prepare()
        // The download leaves a Hugging Face cache beside the folder it copies out, which is all `load` reads.
        let g2p = folder.appending(path: "G2P")
        for item in (try? FileManager.default.contentsOfDirectory(atPath: g2p.path)) ?? [] where item != "mlx-audio" {
            try? FileManager.default.removeItem(at: g2p.appending(path: item))
        }
        await progress(1)
    }

    static func load() async throws -> any Speech {
        // Each sentence has its own length, and MLX keeps buffers of every size for reuse unless capped: without a
        // cap, reading a page grew Berang to 5.3 GB.
        Memory.cacheLimit = 128 * 1024 * 1024
        let misaki = MisakiTextProcessor(cache: lexicons)
        try await misaki.prepare()
        return KittenSpeech(try Kitten2.load(folder: folder), misaki: misaki)
    }
}

struct KittenError: Error, CustomStringConvertible {
    let description: String
}

/// Kitten behind the player's Speech interface. One utterance runs at a time, as MLX works on one stream of
/// commands; each ends with Kitten's 0.15 s pause between chunks.
final class KittenSpeech: Speech, @unchecked Sendable {
    private let kitten: Kitten2
    private let misaki: MisakiTextProcessor
    private let lock = NSLock()
    private var voice = "eleanor"
    private var last: Task<Void, Never>?

    init(_ kitten: Kitten2, misaki: MisakiTextProcessor) {
        self.kitten = kitten
        self.misaki = misaki
    }

    /// Returns MLX's cached buffers once Kitten is let go, as when another engine is chosen.
    deinit { Memory.clearCache() }

    func setVoice(_ name: String) async throws {
        lock.withLock { voice = name }
    }

    func stream(_ text: String) -> AsyncThrowingStream<[Float], Error> {
        AsyncThrowingStream { continuation in
            let task = lock.withLock {
                let previous = last, voice = voice, kitten = kitten, misaki = misaki
                let task = Task {
                    await previous?.value
                    do {
                        try kitten.say(text, voice: voice, misaki: misaki) { continuation.yield($0) }
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
