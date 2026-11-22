// From mlx-audio-swift 0.2.1 (https://github.com/Blaizzy/mlx-audio-swift), MIT License,
// Copyright (c) Prince Canuma. Changed for Kitten TTS 2: see Kitten2.swift.
import Foundation

struct ISTFTNetConfig: Codable {
    let resblockKernelSizes: [Int]
    let upsampleRates: [Int]
    let upsampleInitialChannel: Int
    let resblockDilationSizes: [[Int]]
    let upsampleKernelSizes: [Int]
    let genIstftNFft: Int
    let genIstftHopSize: Int

    enum CodingKeys: String, CodingKey {
        case resblockKernelSizes = "resblock_kernel_sizes"
        case upsampleRates = "upsample_rates"
        case upsampleInitialChannel = "upsample_initial_channel"
        case resblockDilationSizes = "resblock_dilation_sizes"
        case upsampleKernelSizes = "upsample_kernel_sizes"
        case genIstftNFft = "gen_istft_n_fft"
        case genIstftHopSize = "gen_istft_hop_size"
    }
}

struct PLBertConfig: Decodable {
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let hiddenSize: Int
    let intermediateSize: Int
    let maxPositionEmbeddings: Int
    let embeddingSize: Int
    let innerGroupNum: Int
    let numHiddenGroups: Int
    let hiddenDropoutProb: Float
    let attentionProbsDropoutProb: Float
    let typeVocabSize: Int
    let layerNormEps: Float

    enum CodingKeys: String, CodingKey {
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case maxPositionEmbeddings = "max_position_embeddings"
        case embeddingSize = "embedding_size"
        case innerGroupNum = "inner_group_num"
        case numHiddenGroups = "num_hidden_groups"
        case hiddenDropoutProb = "hidden_dropout_prob"
        case attentionProbsDropoutProb = "attention_probs_dropout_prob"
        case typeVocabSize = "type_vocab_size"
        case layerNormEps = "layer_norm_eps"
        case dropout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numHiddenLayers = try container.decode(Int.self, forKey: .numHiddenLayers)
        numAttentionHeads = try container.decode(Int.self, forKey: .numAttentionHeads)
        hiddenSize = try container.decode(Int.self, forKey: .hiddenSize)
        intermediateSize = try container.decode(Int.self, forKey: .intermediateSize)
        maxPositionEmbeddings = try container.decode(Int.self, forKey: .maxPositionEmbeddings)
        embeddingSize = try container.decodeIfPresent(Int.self, forKey: .embeddingSize) ?? 128
        innerGroupNum = try container.decodeIfPresent(Int.self, forKey: .innerGroupNum) ?? 1
        numHiddenGroups = try container.decodeIfPresent(Int.self, forKey: .numHiddenGroups) ?? 1
        hiddenDropoutProb = try container.decodeIfPresent(Float.self, forKey: .hiddenDropoutProb)
            ?? (try container.decodeIfPresent(Float.self, forKey: .dropout) ?? 0.1)
        attentionProbsDropoutProb = try container.decodeIfPresent(Float.self, forKey: .attentionProbsDropoutProb) ?? 0.1
        typeVocabSize = try container.decodeIfPresent(Int.self, forKey: .typeVocabSize) ?? 2
        layerNormEps = try container.decodeIfPresent(Float.self, forKey: .layerNormEps) ?? 1e-12
    }
}
