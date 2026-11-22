import os
import sys

import torch
from pocket_tts import TTSModel

sys.path.insert(0, os.path.dirname(__file__))
from common import run

VOICE = "alba"


class Engine:
    def __init__(self, threads):
        torch.set_num_threads(threads)
        torch.set_num_interop_threads(1)
        self.m = TTSModel.load_model()
        self.state = self.m.get_state_for_audio_prompt(VOICE)
        self.sr = self.m.sample_rate
        self.info = {"model": f"Pocket TTS english 100M ({VOICE})", "device": "cpu",
                     "threads_honored": torch.get_num_threads() == threads,
                     "word_timestamps": "no", "native_speed": False}

    def synth(self, text):
        for chunk in self.m.generate_audio_stream(self.state, text):
            yield chunk.detach().float().numpy()


run(Engine)
