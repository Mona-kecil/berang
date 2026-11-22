import os
import sys

import onnxruntime as ort

sys.path.insert(0, os.path.dirname(__file__))
from common import run

REPO = "KittenML/kitten-tts-2-nano"


def pin_threads(threads):
    real = ort.InferenceSession

    def session(path, sess_options=None, *a, **kw):
        so = sess_options or ort.SessionOptions()
        so.intra_op_num_threads = threads
        so.inter_op_num_threads = 1
        kw["providers"] = ["CPUExecutionProvider"]
        return real(path, so, *a, **kw)

    ort.InferenceSession = session


class Engine:
    sr = 24000

    def __init__(self, threads):
        pin_threads(threads)
        from kittenml import KittenTTS
        self.m = KittenTTS(REPO, backend="onnx")
        self.voice = self.m.available_voices["en"][0]
        self.info = {"model": f"{REPO} ({self.voice})", "device": "cpu", "threads_honored": True,
                     "word_timestamps": "no", "native_speed": True}

    def synth(self, text):
        yield self.m.generate(text, voice=self.voice)


run(Engine)
