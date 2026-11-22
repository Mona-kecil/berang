// From mlx-audio-swift 0.2.1 (https://github.com/Blaizzy/mlx-audio-swift), MIT License,
// Copyright (c) Prince Canuma. Changed for Kitten TTS 2: see Kitten2.swift.
import Foundation
@preconcurrency import MLX
import MLXNN

// MARK: - Instance Normalization

/// Kitten TTS 2's decoder learns a scale and shift per channel (InstanceNorm1d(affine=True)). They start at one
/// and zero, so a norm whose checkpoint has none, as in the prosody predictor, normalizes alone.
class InstanceNorm1d: Module {
    let numFeatures: Int
    let eps: Float
    var weight: MLXArray
    var bias: MLXArray

    init(numFeatures: Int, eps: Float = 1e-5) {
        self.numFeatures = numFeatures
        self.eps = eps
        weight = MLXArray.ones([numFeatures])
        bias = MLXArray.zeros([numFeatures])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let mean = MLX.mean(x, axis: -1, keepDims: true)
        let variance = MLX.variance(x, axis: -1, keepDims: true)
        let normalized = (x - mean) / MLX.sqrt(variance + eps)
        return normalized * weight.reshaped([1, -1, 1]) + bias.reshaped([1, -1, 1])
    }
}

// MARK: - Adaptive Instance Normalization

class AdaIN1d: Module {
    @ModuleInfo var norm: InstanceNorm1d
    @ModuleInfo var fc: Linear

    init(styleDim: Int, numFeatures: Int) {
        _norm = ModuleInfo(wrappedValue: InstanceNorm1d(numFeatures: numFeatures))
        _fc = ModuleInfo(wrappedValue: Linear(styleDim, numFeatures * 2))
    }

    func callAsFunction(_ x: MLXArray, _ s: MLXArray) -> MLXArray {
        var h = fc(s)
        h = h.expandedDimensions(axis: 2)
        let parts = MLX.split(h, parts: 2, axis: 1)
        let gamma = parts[0]
        let beta = parts[1]
        return (1 + gamma) * norm(x) + beta
    }
}

// MARK: - Adaptive Layer Normalization

class AdaLayerNorm: Module {
    let channels: Int
    let eps: Float
    @ModuleInfo var fc: Linear

    init(styleDim: Int, channels: Int, eps: Float = 1e-5) {
        self.channels = channels
        self.eps = eps
        _fc = ModuleInfo(wrappedValue: Linear(styleDim, channels * 2))
    }

    func callAsFunction(_ x: MLXArray, _ s: MLXArray) -> MLXArray {
        var h = fc(s)
        h = h.reshaped([h.shape[0], h.shape[1], 1])
        let parts = MLX.split(h, parts: 2, axis: 1)
        let gamma = parts[0].transposed(2, 0, 1)
        let beta = parts[1].transposed(2, 0, 1)

        let mean = MLX.mean(x, axis: -1, keepDims: true)
        let variance = MLX.variance(x, axis: -1, keepDims: true)
        let normalized = (x - mean) / MLX.sqrt(variance + eps)

        return (1 + gamma) * normalized + beta
    }
}
