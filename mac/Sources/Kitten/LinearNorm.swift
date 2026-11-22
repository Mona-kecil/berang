// From mlx-audio-swift 0.2.1 (https://github.com/Blaizzy/mlx-audio-swift), MIT License,
// Copyright (c) Prince Canuma. Changed for Kitten TTS 2: see Kitten2.swift.
import Foundation
@preconcurrency import MLX
import MLXNN

class LinearNorm: Module {
    @ModuleInfo(key: "linear_layer") var linearLayer: Linear

    init(inDim: Int, outDim: Int) {
        _linearLayer = ModuleInfo(wrappedValue: Linear(inDim, outDim), key: "linear_layer")
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        linearLayer(x)
    }
}
