"""music - algorithmic layered-stem music generator (AUD-T4).

  flavours.py   scales, the 8 faction Flavours + the menu flavour, instrument voices (drums, bass, pads, leads), drum feels
  arrange.py    Flavour + style + bar count -> four aligned circular stems (drums, bass, pads, lead)
  stingers.py   riser / victory / defeat / match-start one-shots in the faction's mode and timbre
  mixdown.py    stem balance, shared master gain, circular look-ahead limiter, Vorbis encode, manifest entries
  verify.py     tempo, scale, loop and loudness checks (decoded shipped files) + audition sheets

Everything is numpy-only (dsp.py), seeded and deterministic; stems are rendered circularly so the loop is seamless by construction.
"""
