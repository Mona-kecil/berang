import os
import sys

import onnxruntime as ort
from kokoro_onnx import Kokoro

sys.path.insert(0, os.path.dirname(__file__))
from common import run

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INT8 = "int8" in os.path.basename(__file__)
MODEL = f"{ROOT}/models/kokoro/kokoro-v1.0{'.int8' if INT8 else ''}.onnx"
VOICE = "af_heart"


class Engine:
    sr = 24000
    info = {"model": f"Kokoro-82M v1.0 ONNX {'int8' if INT8 else 'fp32'} ({VOICE})", "device": "cpu",
            "threads_honored": True, "word_timestamps": "yes (create_timed)", "native_speed": True}

    def __init__(self, threads):
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        so.inter_op_num_threads = 1
        sess = ort.InferenceSession(MODEL, so, providers=["CPUExecutionProvider"])
        self.k = Kokoro.from_session(sess, f"{ROOT}/models/kokoro/voices-v1.0.bin")

    def synth(self, text):
        audio, sr = self.k.create(text, voice=VOICE, lang="en-us")
        assert sr == self.sr
        yield audio


run(Engine)
