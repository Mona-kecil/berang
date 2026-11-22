import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXNN

/// Kitten TTS 2 nano for one language (Apache-2.0, KittenML), run on MLX from its float32 PyTorch weights.
///
/// It is Kitten TTS 0.8's network, which mlx-audio-swift ports, at nano's sizes, with two changes from that port:
/// the decoder's instance norms learn a scale and shift, and the sine generator starts its harmonics at uniform
/// random phases, as Kitten's PyTorch code does. Text reaches it as phonemes (see `tokens`).
public final class Kitten2: Module, @unchecked Sendable {
    public static let sampleRate = 24_000

    @ModuleInfo var bert: Albert
    @ModuleInfo(key: "bert_encoder") var bertEncoder: Linear
    @ModuleInfo var predictor: KittenProsodyPredictor
    @ModuleInfo(key: "text_encoder") var textEncoder: KittenTextEncoder
    @ModuleInfo var decoder: KittenDecoder

    private let vocab: [Character: Int32]
    private let packs: [String: MLXArray]

    /// The language's voices, in the order Kitten lists them: the first speaks when none is chosen.
    public let voices: [Voice]

    public struct Voice: Sendable {
        /// The voice pack's name in the voice file, such as "eleanor".
        public let key: String
        public let name: String
        /// Such as "Somber historian (female)".
        public let description: String
    }

    /// Whether the decoder adds its random phase and noise. Off, its output is deterministic, to compare with a
    /// reference.
    public static var noise: Bool {
        get { kittenNoiseOn }
        set { kittenNoiseOn = newValue }
    }

    private init(config: KittenTTSConfig, vocab: [Character: Int32], packs: [String: MLXArray], voices: [Voice]) {
        self.vocab = vocab
        self.packs = packs
        self.voices = voices
        _bert = ModuleInfo(wrappedValue: Albert(config: config.plbert, vocabSize: config.nToken))
        _bertEncoder = ModuleInfo(wrappedValue: Linear(config.plbert.hiddenSize, config.hiddenDim), key: "bert_encoder")
        _predictor = ModuleInfo(wrappedValue: KittenProsodyPredictor(
            styleDim: config.styleDim, dHid: config.hiddenDim, nLayers: config.nLayer, maxDur: config.maxDur, dropout: 0))
        _textEncoder = ModuleInfo(wrappedValue: KittenTextEncoder(
            channels: config.hiddenDim, kernelSize: config.textEncoderKernelSize, depth: config.nLayer,
            nSymbols: config.nToken), key: "text_encoder")
        _decoder = ModuleInfo(wrappedValue: KittenDecoder(config: config))
    }

    /// Loads one language of a folder laid out as KittenML/kitten-tts-2-nano: config.json, vocab.json, and the
    /// language's weights (kitten_tts_2_nano_<language>.safetensors) and voice packs (voices_<language>.npz).
    public static func load(folder: URL, language: String = "en") throws -> Kitten2 {
        let weights = folder.appending(path: "kitten_tts_2_nano_\(language).safetensors")
        let voices = folder.appending(path: "voices_\(language).npz")
        let vocab = folder.appending(path: "vocab.json")
        struct Listing: Decodable { let voices: [String: [Entry]]; struct Entry: Decodable { let key, name, description: String } }
        let listing = try JSONDecoder().decode(Listing.self, from: Data(contentsOf: folder.appending(path: "config.json")))
        let config = try JSONDecoder().decode(KittenTTSConfig.self, from: Data(nanoConfig.utf8))
        let table = try JSONDecoder().decode([String: Int32].self, from: Data(contentsOf: vocab))
        var symbols: [Character: Int32] = [:]
        for (symbol, id) in table where symbol.count == 1 { symbols[symbol.first!] = id }
        let packs = try NumpyArchive.load(url: voices).mapValues { $0.asType(.float32) }
        let listed = (listing.voices[language] ?? []).filter { packs[$0.key] != nil }
            .map { Voice(key: $0.key, name: $0.name, description: $0.description) }
        let model = Kitten2(config: config, vocab: symbols, packs: packs, voices: listed)
        try model.update(parameters: ModuleParameters.unflattened(mlxWeights(MLX.loadArrays(url: weights))),
                         verify: .noUnusedKeys)
        model.train(false)
        return model
    }

    /// The tokens Kitten 2 reads for `phonemes`: the start token, each symbol in the vocabulary (parentheses read as
    /// commas, anything else dropped), the end token, and the start token again.
    public func tokens(_ phonemes: String) -> [Int32] {
        var ids: [Int32] = [0]
        for symbol in phonemes {
            if let id = vocab[symbol] { ids.append(id) } else if "()".contains(symbol), let comma = vocab[","] { ids.append(comma) }
        }
        return ids + [10, 0]
    }

    /// The style vector a voice uses for `count` tokens: its pack holds one per length.
    public func style(_ voice: String, tokens count: Int) -> MLXArray? {
        guard let pack = packs[voice.lowercased()] else { return nil }
        let row = min(count - 1, pack.shape[0] - 1)
        return pack[row ..< row + 1]
    }

    /// Speaks `phonemes` in `voice` and returns its audio, trimmed and faded as kittenml does: the end token's frames
    /// are cut, and the start token's too unless `keepStart`, then 5 ms fades.
    public func speak(_ phonemes: String, voice: String, speed: Float = 1, keepStart: Bool = true) -> [Float] {
        let ids = tokens(phonemes)
        guard ids.count > 3, let style = style(voice, tokens: ids.count) else { return [] }
        let (audio, durations) = synthesize(ids, style: style, speed: speed)
        var wave = audio.map { max(-1, min(1, $0)) }
        let frames = max(Int(durations.reduce(0, +)), 1)
        let perFrame = max(1, Int((Double(wave.count) / Double(frames)).rounded()))
        let lead = keepStart ? 0 : max(0, Int(durations.first ?? 0) - 1) * perFrame
        let trail = max(0, Int(durations.last ?? 0) - 1) * perFrame
        if lead + trail + perFrame < wave.count { wave = Array(wave[lead ..< wave.count - trail]) }
        let fade = min(120, wave.count / 8)
        for i in 0 ..< fade {
            let gain = Float(i) / Float(max(fade - 1, 1))
            wave[i] *= gain
            wave[wave.count - 1 - i] *= gain
        }
        return wave
    }

    /// The network: tokens, a style vector, and a speed, to the waveform and each token's duration in frames.
    public func synthesize(_ tokens: [Int32], style refS: MLXArray, speed: Float) -> (audio: [Float], durations: [Int32]) {
        let out = run(tokens, style: refS, speed: speed)
        return (out.audio, out.durations)
    }

    /// `synthesize`, with the predicted pitch (F0) and energy (N) at twice the frame rate, to check against a
    /// reference.
    public func run(_ tokens: [Int32], style refS: MLXArray, speed: Float)
        -> (audio: [Float], durations: [Int32], f0: [Float], n: [Float], rawDurations: [Float]) {
        let inputIds = MLXArray(tokens).reshaped([1, -1])
        let seqLen = tokens.count
        let inputLengths = MLXArray([Int32(seqLen)])
        let textMask = (MLXArray(Array(0 ..< Int32(seqLen))).reshaped([1, -1]) + 1) .> inputLengths.reshaped([-1, 1])
        let (bertOut, _) = bert(inputIds, attentionMask: MLXArray(1) - textMask.asType(.int32))
        let dEn = bertEncoder(bertOut).transposed(0, 2, 1)
        let s = refS[0..., 128...]
        let d = predictor.textEncoder(dEn, style: s, textLengths: inputLengths, mask: textMask)
        let (x, _) = predictor.lstm(d)
        let raw = MLX.sigmoid(predictor.durationProj(x)).sum(axis: -1)
        let durations = MLX.clip(MLX.round(raw / speed), min: 1).asType(.int32)[0]
        let perToken: [Int32] = durations.asArray(Int32.self)
        let frameToken = perToken.enumerated().flatMap { Array(repeating: Int32($0.offset), count: Int($0.element)) }
        let alignment = MLXArray.zeros([seqLen, frameToken.count])
        alignment[MLXArray(frameToken), MLXArray(Array(0 ..< Int32(frameToken.count)))] = MLXArray(Float(1))
        let aligned = alignment.expandedDimensions(axis: 0)
        let (f0, n) = predictor.f0Ntrain(MLX.matmul(d.transposed(0, 2, 1), aligned), s)
        let tEn = textEncoder(inputIds, inputLengths: inputLengths, mask: textMask)
        let audio = decoder(MLX.matmul(tEn, aligned), f0, n, refS[0..., ..<128])
        return (audio[0].asArray(Float.self), perToken, f0.reshaped([-1]).asArray(Float.self), n.reshaped([-1]).asArray(Float.self),
                raw.reshaped([-1]).asArray(Float.self))
    }
}

/// PyTorch's names and layouts to this port's: LSTM weights take the port's names, layer norms' gamma and beta
/// become weight and bias, every convolution weight goes from [out, in, kernel] to [out, kernel, in], and the
/// generator's Snake alphas, [1, channels, 1], lose a dot from their names.
func mlxWeights(_ weights: [String: MLXArray]) -> [String: MLXArray] {
    let lstm = ["weight_ih": "Wx", "weight_hh": "Wh", "bias_ih": "bias_ih", "bias_hh": "bias_hh"]
    var out: [String: MLXArray] = [:]
    for (key, value) in weights {
        var name = key.replacingOccurrences(of: ".alpha1.", with: ".alpha1_").replacingOccurrences(of: ".alpha2.", with: ".alpha2_")
        if name.hasSuffix(".gamma") { name = String(name.dropLast("gamma".count)) + "weight" }
        if name.hasSuffix(".beta") { name = String(name.dropLast("beta".count)) + "bias" }
        for (torch, port) in lstm {
            if name.hasSuffix(".\(torch)_l0") { name = String(name.dropLast("\(torch)_l0".count)) + "\(port)_forward" }
            if name.hasSuffix(".\(torch)_l0_reverse") { name = String(name.dropLast("\(torch)_l0_reverse".count)) + "\(port)_backward" }
        }
        out[name] = value.ndim == 3 && !name.contains(".alpha") ? value.transposed(0, 2, 1) : value
    }
    return out
}

/// Kitten TTS 2 nano's architecture, from KittenML/kitten-tts-2-nano's config.json, in the port's terms.
private let nanoConfig = """
{"model_type": "kitten_tts", "hidden_dim": 256, "max_conv_dim": 192, "decoder_out_dim": 192, "asr_res_dim": 64,
 "max_dur": 50, "n_layer": 3, "n_mels": 80, "n_token": 178, "style_dim": 128, "text_encoder_kernel_size": 5,
 "sample_rate": 24000, "voices_path": "voices.npz",
 "plbert": {"num_hidden_layers": 12, "num_attention_heads": 12, "hidden_size": 768, "intermediate_size": 2048,
            "max_position_embeddings": 512, "embedding_size": 128, "inner_group_num": 1, "num_hidden_groups": 1,
            "hidden_dropout_prob": 0.0, "attention_probs_dropout_prob": 0.0, "type_vocab_size": 2,
            "layer_norm_eps": 1e-12},
 "istftnet": {"resblock_kernel_sizes": [3, 3], "upsample_rates": [10, 6], "upsample_initial_channel": 192,
              "resblock_dilation_sizes": [[1, 3, 5], [1, 3, 5]], "upsample_kernel_sizes": [20, 12],
              "gen_istft_n_fft": 20, "gen_istft_hop_size": 5}}
"""
