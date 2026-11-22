// From mlx-audio-swift 0.2.1 (https://github.com/Blaizzy/mlx-audio-swift), MIT License,
// Copyright (c) Prince Canuma. Changed for Kitten TTS 2: see Kitten2.swift.
import Foundation

struct KittenTTSConfig: Decodable {
    let modelType: String
    let hiddenDim: Int
    let maxConvDim: Int
    let maxDur: Int
    let nLayer: Int
    let nMels: Int
    let nToken: Int
    let styleDim: Int
    let textEncoderKernelSize: Int
    let asrResDim: Int
    let sampleRate: Int
    let decoderOutDim: Int?
    let voicesPath: String
    let speedPriors: [String: Float]?
    let voiceAliases: [String: String]?
    let plbert: PLBertConfig
    let istftnet: ISTFTNetConfig

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case hiddenDim = "hidden_dim"
        case maxConvDim = "max_conv_dim"
        case maxDur = "max_dur"
        case nLayer = "n_layer"
        case nMels = "n_mels"
        case nToken = "n_token"
        case styleDim = "style_dim"
        case textEncoderKernelSize = "text_encoder_kernel_size"
        case asrResDim = "asr_res_dim"
        case sampleRate = "sample_rate"
        case decoderOutDim = "decoder_out_dim"
        case voicesPath = "voices_path"
        case speedPriors = "speed_priors"
        case voiceAliases = "voice_aliases"
        case plbert
        case istftnet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decode(String.self, forKey: .modelType)
        hiddenDim = try container.decode(Int.self, forKey: .hiddenDim)
        maxConvDim = try container.decode(Int.self, forKey: .maxConvDim)
        maxDur = try container.decode(Int.self, forKey: .maxDur)
        nLayer = try container.decode(Int.self, forKey: .nLayer)
        nMels = try container.decode(Int.self, forKey: .nMels)
        nToken = try container.decode(Int.self, forKey: .nToken)
        styleDim = try container.decode(Int.self, forKey: .styleDim)
        textEncoderKernelSize = try container.decode(Int.self, forKey: .textEncoderKernelSize)
        asrResDim = try container.decode(Int.self, forKey: .asrResDim)
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 24000
        decoderOutDim = try container.decodeIfPresent(Int.self, forKey: .decoderOutDim)
        voicesPath = try container.decodeIfPresent(String.self, forKey: .voicesPath) ?? "voices.npz"
        speedPriors = try container.decodeIfPresent([String: Float].self, forKey: .speedPriors)
        voiceAliases = try container.decodeIfPresent([String: String].self, forKey: .voiceAliases)
        plbert = try container.decode(PLBertConfig.self, forKey: .plbert)
        istftnet = try container.decode(ISTFTNetConfig.self, forKey: .istftnet)
    }
}
