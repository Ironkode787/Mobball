"""KINGPIN audio generator — every byte of game audio is synthesised here.

No samples are downloaded, recorded or licensed: `generate.py` renders the whole SFX
set and the city-1 stem stack from first principles and writes them into
`assets/audio/`. See specs/audio-pipeline.md for the contract.
"""

__all__ = ["analysis", "generate", "music", "sfx", "synth", "theory", "voice"]
