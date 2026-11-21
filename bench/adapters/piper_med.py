import json
import os
import sys

import numpy as np
import onnxruntime as ort
from piper import PiperVoice
from piper.config import PiperConfig

sys.path.insert(0, os.path.dirname(__file__))
from common import run

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUALITY = "high" if "high" in os.path.basename(__file__) else "medium"
MODEL = f"{ROOT}/models/piper/en_US-lessac-{QUALITY}.onnx"


class Engine:
    info = {"model": f"Piper en_US-lessac-{QUALITY}", "device": "cpu", "threads_honored": True,
            "word_timestamps": "phoneme alignments (include_alignments)", "native_speed": True}

    def __init__(self, threads):
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        so.inter_op_num_threads = 1
        sess = ort.InferenceSession(MODEL, so, providers=["CPUExecutionProvider"])
        self.v = PiperVoice(session=sess, config=PiperConfig.from_dict(json.load(open(MODEL + ".json"))))
        self.sr = self.v.config.sample_rate

    def synth(self, text):
        for chunk in self.v.synthesize(text):
            yield np.asarray(chunk.audio_float_array, dtype=np.float32)


run(Engine)
