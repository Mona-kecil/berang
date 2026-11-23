# Qwen3-TTS Indonesian on MLX

Measures [alkhrzmy/qwen3-tts-0.6b-indonesian](https://huggingface.co/alkhrzmy/qwen3-tts-0.6b-indonesian) (Apache-2.0) as Berang would run it. Context and the comparison with other Indonesian voices: see the issue for Indonesian.

## Make the shrunk model

```sh
uv run --no-project --with mlx-audio python -m mlx_audio.convert \
  --hf-path alkhrzmy/qwen3-tts-0.6b-indonesian --mlx-path q4 -q --q-bits 4 --dtype bfloat16
uv run --no-project --with mlx python shrink.py q4 q4s keep
```

`shrink.py` quantizes the 151,936-entry text embedding to 4 bits, which mlx-audio leaves at bfloat16 (622 MB), and stores the speech tokenizer at float16 instead of float32. The `drop` mode also removes the speech tokenizer's encoder, which only voice cloning uses, but mlx-audio-swift 0.2.1 refuses to load a tokenizer without it.

## Measure

`mac/Sources/qwen-spike` speaks a text sentence by sentence through mlx-audio-swift, as the player does. It prints the time to first audio, the speed against real time, and the process footprint:

```sh
cd mac && swift build -c release --product qwen-spike
cp -R build/Berang.app/Contents/Resources/*.bundle .build/release/   # MLX's Metal shaders
.build/release/qwen-spike q4s text.txt 64
```

On an M1 with 8 GB, with a 64 MB MLX cache cap, speaking three Indonesian sentences:

| | Disk | Footprint after load | Peak while speaking | Speed | First audio |
|---|---|---|---|---|---|
| mlx-audio's 4-bit | 1.6 GB | 1.8 GB | 2.2 GB | 1.3× real time | 0.55 s |
| Shrunk (`shrink.py ... keep`) | 868 MB | 1.0 GB | 1.4 GB | 1.3× real time | 0.5 s |

Whisper large-v3-turbo transcribed every word of the shrunk model's output.
