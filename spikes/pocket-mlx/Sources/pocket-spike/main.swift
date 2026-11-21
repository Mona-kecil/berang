// Times Pocket TTS 100M in Swift on MLX, the same way bench/adapters/common.py times the Python build.
// usage: pocket-spike <corpus.json> <out-dir> [reference.wav | voice.safetensors]
// With no voice it speaks as the bundled "alba" voice. A .wav is cloned; a .safetensors is a voice saved by an earlier run.
import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS

struct Corpus: Decodable {
    struct Passage: Decodable { let id: String; let sentences: [String] }
    let passages: [Passage]
}

let args = CommandLine.arguments
let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let out = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func seconds(since start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

let env = ProcessInfo.processInfo.environment
// POCKET_DEVICE=cpu runs MLX on the CPU instead of the GPU.
let device = env["POCKET_DEVICE"] ?? "gpu"
if device == "cpu" { Device.setDefault(device: Device(.cpu)) }
// POCKET_CACHE_MB caps the memory MLX keeps cached for reuse.
if let mb = env["POCKET_CACHE_MB"].flatMap(Int.init) { Memory.cacheLimit = mb * 1024 * 1024 }
// POCKET_CLONE=raw passes the reference audio on every call; the default encodes it once into a voice file.
let cloneMode = env["POCKET_CLONE"] ?? "embed"

var t = ContinuousClock.now
let model = try await TTS.loadModel(modelRepo: "mlx-community/pocket-tts")
let loadS = seconds(since: t)
let sr = model.sampleRate

var ref: MaterializedArray?
var voice: String? = "alba"
var embedS: Double?
if args.count > 3, args[3].hasSuffix(".safetensors") {
    voice = args[3]  // a voice file saved by an earlier run
} else if args.count > 3 {
    let (_, audio) = try loadAudioArray(from: URL(fileURLWithPath: args[3]), sampleRate: sr)
    voice = nil
    if cloneMode == "raw" {
        ref = audio
    } else {
        t = ContinuousClock.now
        voice = try embedVoice(audio, to: out.appending(path: "voice.safetensors")).path
        embedS = seconds(since: t)
    }
}

/// Encodes a reference clip into the voice embedding the model conditions on, as PocketTTSModel.encodeAudio does,
/// and saves it where `voice:` can load it. This runs the speaker encoder once instead of on every call.
@MainActor func embedVoice(_ audio: MLXArray, to url: URL) throws -> URL {
    let pocket = model as! PocketTTSModel
    var clip = audio.ndim == 1 ? audio.expandedDimensions(axes: [0, 1]) : audio
    if let maxS = pocket.config.audioPromptMaxDuration {
        clip = clip[.ellipsis, ..<min(clip.shape[2], Int(maxS * Double(sr)))]
    }
    let latents = pocket.mimi.encodeToLatent(clip.asType(.float32)).transposed(0, 2, 1).asType(.float32)
    let emb = matmul(latents, pocket.speaker_proj_weight.transposed(1, 0))
    try MLX.save(arrays: ["emb": emb], url: url)
    return url
}

/// Speaks `sentences` one call each, as the player does per block. Returns first-audio time, generation time, samples.
@MainActor func speak(_ sentences: [String]) async throws -> (first: Double?, gen: Double, samples: [Float]) {
    let start = ContinuousClock.now
    var first: Double?, samples: [Float] = []
    for s in sentences {
        for try await event in model.generateStream(
            text: s, voice: voice, refAudio: ref, refText: nil, language: nil,
            generationParameters: model.defaultGenerationParameters, streamingInterval: 0.08
        ) {
            if case .audio(let chunk) = event {
                first = first ?? seconds(since: start)
                samples += chunk.asArray(Float.self)
            }
        }
    }
    return (first, seconds(since: start), samples)
}

t = ContinuousClock.now
_ = try await speak(["Warming up."])
let coldS = seconds(since: t)

var metrics: [String: Any] = ["load_s": loadS, "cold_first_s": coldS, "device": device, "voice": args.count < 4 ? "alba" : args[3].hasSuffix(".safetensors") ? "clone-file" : "clone-\(cloneMode)", "embed_s": embedS ?? 0, "cache_mb": env["POCKET_CACHE_MB"] ?? "default"]
for p in corpus.passages where ["short", "para", "long"].contains(p.id) {
    let r = try await speak(p.sentences)
    let audioS = Double(r.samples.count) / Double(sr)
    metrics[p.id] = ["first_audio_s": r.first ?? -1, "synth_s": r.gen, "audio_s": audioS, "rtf": r.gen / audioS]
    try AudioUtils.writeWavFile(samples: r.samples, sampleRate: sr, fileURL: out.appending(path: "\(p.id).wav"))
    print(String(format: "%@: first audio %.3fs, %.1fs audio in %.1fs, rtf %.3f", p.id, r.first ?? -1, audioS, r.gen, r.gen / audioS))
}
try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appending(path: "metrics.json"))
print(String(format: "load %.2fs, cold first call %.2fs", loadS, coldS))
