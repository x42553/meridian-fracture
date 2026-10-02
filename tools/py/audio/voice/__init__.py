"""voice - announcer / EVA lines and unit acknowledgement responses (AUD-T5).

  lines.py        the line catalogue (mirror of game/data/audio/announcer.json) -> one job per pack x line x take
  cache.py        text + voice + model hash cache of raw TTS output (.cache/audio/tts)
  tts_kokoro.py   Kokoro-82M (Apache-2.0) through kokoro-onnx: the shipped announcer voices
  tts_piper.py    Piper (CC0 / public-domain voices only): fast iteration mode, not used for shipped assets
  chains.py       numpy computer / officer / radio effect chains (replace the ffmpeg chains of the spike; ffmpeg is not needed)
  responses.py    unit acknowledgement bleeps (squelch + faction motif + squelch)
  build.py        job planning, rendering, manifest entries, QA and audition sheets

Build-time only.  Nothing here ships; only the OGGs and their captions (announcer.json) do.
"""
