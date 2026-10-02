"""piper_batch.py - run inside .cache/venv_piper: synthesize the announcer lines with a Piper voice, print RTF as JSON."""
import json, sys, time, wave
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from piper import PiperVoice
model, outdir, lines = sys.argv[1], Path(sys.argv[2]), json.loads(sys.argv[3])
outdir.mkdir(parents=True, exist_ok=True)
t0 = time.time(); voice = PiperVoice.load(model); t_load = time.time() - t0
audio_s = 0.0; t1 = time.time()
for key, text in lines.items():
    with wave.open(str(outdir / f"{key}.wav"), "wb") as wf:
        voice.synthesize_wav(text, wf)
    with wave.open(str(outdir / f"{key}.wav"), "rb") as r:
        audio_s += r.getnframes() / r.getframerate()
t_syn = time.time() - t1
print(json.dumps({"model": Path(model).name, "load_s": round(t_load, 2), "synth_s": round(t_syn, 2), "audio_s": round(audio_s, 2), "rtf": round(t_syn / audio_s, 3), "sr": voice.config.sample_rate}))
