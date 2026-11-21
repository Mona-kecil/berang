import os
import subprocess
import sys
import tempfile

import soundfile as sf

sys.path.insert(0, os.path.dirname(__file__))
from common import run

VOICE = os.environ.get("SAY_VOICE", "Samantha")


class Say:
    sr = 22050
    info = {"model": f"macOS say ({VOICE})", "device": "cpu", "threads_honored": False,
            "word_timestamps": "yes via AVSpeechSynthesizer callbacks", "native_speed": True}

    def synth(self, text):
        with tempfile.NamedTemporaryFile(suffix=".wav") as f:
            subprocess.run(["say", "-v", VOICE, "-o", f.name, "--file-format=WAVE",
                            f"--data-format=LEF32@{self.sr}", text], check=True)
            audio, _ = sf.read(f.name, dtype="float32")
        yield audio


run(lambda threads: Say())
