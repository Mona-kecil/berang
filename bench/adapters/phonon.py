import os
import sys

import ptts

sys.path.insert(0, os.path.dirname(__file__))
from common import run


class Engine:
    def __init__(self, threads):
        ptts.set_num_threads(threads)
        self.tts = ptts.TTS(lang="en", device="cpu", quant="q8")
        self.sr = self.tts.sample_rate
        self.info = {"model": "Phonon 31m en q8 (default voice)", "device": "cpu",
                     "threads_honored": ptts.get_num_threads() == threads,
                     "word_timestamps": "unknown", "native_speed": "duration_delta condition"}

    def synth(self, text):
        with self.tts.stream(text) as audio:
            for chunk in audio:
                yield chunk


run(Engine)
