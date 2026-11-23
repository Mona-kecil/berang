# Shrinks a 4-bit Qwen3-TTS folder: the text embedding goes to 4 bits like the rest, and the speech tokenizer to
# float16, optionally without its encoder, which only voice cloning uses.
import json, shutil, sys, mlx.core as mx
src, dst, drop_encoder = sys.argv[1], sys.argv[2], sys.argv[3] == "drop"
shutil.copytree(src, dst, dirs_exist_ok=True, copy_function=shutil.copyfile)
w = mx.load(f"{src}/model.safetensors")
k = "talker.model.text_embedding.weight"
q, s, b = mx.quantize(w[k], group_size=64, bits=4)
w[k], w[k.replace("weight", "scales")], w[k.replace("weight", "biases")] = q, s, b
import os
os.remove(f"{dst}/model.safetensors")
mx.save_safetensors(f"{dst}/model.safetensors", w)
idx = f"{dst}/model.safetensors.index.json"
try:
    j = json.load(open(idx))
    for x in ("scales", "biases"): j["weight_map"][k.replace("weight", x)] = "model.safetensors"
    json.dump(j, open(idx, "w"))
except FileNotFoundError: pass
t = mx.load(f"{src}/speech_tokenizer/model.safetensors")
t = {n: (a.astype(mx.float16) if a.dtype == mx.float32 else a) for n, a in t.items() if not (drop_encoder and n.startswith("encoder."))}
os.remove(f"{dst}/speech_tokenizer/model.safetensors")
mx.save_safetensors(f"{dst}/speech_tokenizer/model.safetensors", t)
