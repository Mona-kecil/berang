# Pocket TTS 100M in Swift

This spike answers #15: can berang run Pocket TTS 100M from Swift, and clone a voice, as well as the Python build does?

Yes. Through [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) 0.2.1 on the GPU, Pocket 100M starts speaking as fast as Python, clones a voice equally well, and uses less memory. It generates about 20% slower than Python but still runs 2.8 times faster than real time.

## Results

M1 MacBook Air, 8 GB, macOS 26.6. These are medians of 3 interleaved runs over `bench/corpus.json`, one model call per sentence, as the player makes them. The Python row comes from `bench/results/summary.md`: Pocket 100M on 2 CPU threads.

| Build | Voice | First audio | Generation time per second of audio | Peak memory |
|---|---|---|---|---|
| Python, CPU | alba | 0.068 s | 0.28 s | 1.17 GB |
| Swift, MLX GPU | alba | 0.069 s | 0.35 s | 1.08 GB |
| Swift, MLX GPU | cloned, from a saved voice file | 0.076 s | 0.35 s | 1.12 GB |
| Swift, MLX GPU, 256 MB cache cap | cloned, from a saved voice file | 0.082 s | 0.36 s | 0.89 GB |
| Swift, MLX GPU | cloned, reference audio passed on every call | 0.27 s | 0.40 s | 2.64 GB |
| Swift, MLX CPU | alba | 0.31 s | 2.35 s | 0.62 GB |

Quality matches the Python build:

- Word error rate, from transcribing the audio with Parakeet, is 0 to 0.5% on the paragraph and the 25-sentence passage in every Swift configuration. The Python build scored 0%.
- Speaker similarity to a 14-second reference recording is 0.84 to 0.86 (Resemblyzer cosine). The Python clone scored 0.857, and the stock alba voice scored 0.53.

## Findings

1. **Encode the reference once.** The library's public API re-encodes the reference audio on every call. That costs 0.2 to 0.4 s of first audio and 1.5 GB of memory. `embedVoice` in `main.swift` runs the speaker encoder once, which takes 0.24 s for a 14-second clip. It saves the result as a 729 KB `.safetensors` voice file, and later calls load that file like a stock voice.
2. **Use the GPU.** On the CPU, MLX is slower than real time.
3. **Cap the MLX cache.** A 256 MB cap cuts peak memory by about 200 MB and costs about 4% speed.
4. **The top playback speed is limited.** At 0.35 s per second of audio, Pocket keeps up with playback up to about 2.8×. Faster playback needs read-ahead or another voice (#21).
5. **The app's build must change.** MLX compiles Metal shaders, which `swift build` cannot do. The app must build with `xcodebuild`, which the signed app bundle (#4) needs anyway. Xcode also needs its Metal toolchain: `xcodebuild -downloadComponent MetalToolchain`.
6. **Weights.** `mlx-community/pocket-tts` (240 MB, not gated) includes the speaker encoder, so cloning needs no Hugging Face token. The weights are CC-BY-4.0. Kyutai gates its own copy behind terms about cloning voices without consent. The voice cloning setup (#16) should record the user's own voice and ask for their consent.

## Run it

```sh
xcodebuild -downloadComponent MetalToolchain   # once
xcodebuild -scheme PocketSpike -destination 'platform=macOS,arch=arm64' \
  -configuration Release -derivedDataPath .xcbuild build
BIN=.xcbuild/Build/Products/Release/pocket-spike
$BIN ../../bench/corpus.json out/alba                       # stock voice
$BIN ../../bench/corpus.json out/clone reference.wav        # clone, saves out/clone/voice.safetensors
$BIN ../../bench/corpus.json out/file out/clone/voice.safetensors
```

Each run writes `short.wav`, `para.wav`, `long.wav`, and `metrics.json`. `POCKET_DEVICE=cpu` switches to the CPU, `POCKET_CACHE_MB=256` caps the cache, and `POCKET_CLONE=raw` passes the reference audio on every call. To score word errors, pass the output folders to `bench/score.py`.
