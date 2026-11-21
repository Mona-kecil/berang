import os
import sys
import tempfile

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = f"{ROOT}/models/moss_nano/src"
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(1, SRC)
from common import run
from onnx_tts_runtime import OnnxTtsRuntime

VOICE = "Ava"


class Engine:
    def __init__(self, threads):
        self.r = OnnxTtsRuntime(model_dir=f"{SRC}/models", thread_count=threads, execution_provider="cpu")
        self.sr = int(self.r.codec_meta["codec_config"]["sample_rate"])
        self.tmp = tempfile.mkdtemp()
        self.info = {"model": f"MOSS-TTS-Nano-100M ONNX ({VOICE})", "device": "cpu", "threads_honored": True,
                     "word_timestamps": "no", "native_speed": False}

    def synth(self, text):
        res = self.r.synthesize(text=text, voice=VOICE, enable_wetext=False, enable_normalize_tts_text=True,
                                output_audio_path=f"{self.tmp}/x.wav")
        w = np.asarray(res["waveform"], dtype=np.float32)
        if w.ndim == 2:
            w = w.mean(axis=0 if w.shape[0] < w.shape[1] else 1)
        yield w


run(Engine)
