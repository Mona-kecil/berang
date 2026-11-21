import os
import sys

import onnxruntime as ort

sys.path.insert(0, os.path.dirname(__file__))
from common import run

NAME = os.path.basename(__file__)[:-3]
REPO, VOICE = {
    "kitten08_mini": ("KittenML/kitten-tts-mini-0.8", "expr-voice-2-f"),
    "kitten2_nano": ("KittenML/kitten-tts-2-nano", None),
    "kitten2_mini": ("KittenML/kitten-tts-2-mini", None),
}[NAME]


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
        self.m = KittenTTS(REPO, backend="onnx") if "kitten2" in NAME else KittenTTS(REPO)
        self.voice = VOICE or self.m.available_voices["en"][0]
        self.info = {"model": f"{REPO} ({self.voice})", "device": "cpu", "threads_honored": True,
                     "word_timestamps": "no", "native_speed": True}

    def synth(self, text):
        yield self.m.generate(text, voice=self.voice)


run(Engine)
