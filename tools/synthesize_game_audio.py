"""Render original v2 game audio, completion cue, and auditions with NumPy.

No external music, recordings, or samples are used. This is offline asset
generation; nothing here executes on a player's device. Original v1 auditions
are preserved. Run with the workspace's bundled Python, which includes NumPy.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CarpetToy" / "assets" / "audio"
AUDITIONS = ROOT / "design" / "audio_sketches"
SR = 44100
RNG = np.random.default_rng(2026093002)
ASSETS.mkdir(parents=True, exist_ok=True)
AUDITIONS.mkdir(parents=True, exist_ok=True)


def fade_curve(t, attack, release, duration):
    """Raised-cosine endpoints avoid hard note attacks and cutoffs."""
    fade_in = .5 - .5 * np.cos(np.pi * np.clip(t / attack, 0, 1))
    fade_out = .5 - .5 * np.cos(np.pi * np.clip((duration - t) / release, 0, 1))
    return fade_in * fade_out


def note(midi, duration, pad=False):
    t = np.arange(round(duration * SR)) / SR
    frequency = 440 * 2 ** ((midi - 69) / 12)
    phase = 2 * np.pi * frequency * t
    # Harmonics are deliberately quiet and exactly in tune. No metallic
    # inharmonic partials, noise transients, or sharp tick-like attacks.
    signal = np.sin(phase) + .10 * np.sin(2 * phase) + .012 * np.sin(3 * phase)
    if pad:
        envelope = fade_curve(t, .6, 1.25, duration)
    else:
        envelope = fade_curve(t, .055, .32, duration) * np.exp(-t / 1.35)
    return signal * envelope


def add_circular(target, source, seconds, amplitude=1, pan=0):
    start = round(seconds * SR) % len(target)
    gains = np.array([np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)])
    source = source[:, None] * gains * amplitude
    n = min(len(source), len(target) - start)
    target[start:start + n] += source[:n]
    if n < len(source):
        target[:len(source) - n] += source[n:]


def circular_lowpass(signal, cutoff):
    frequencies = np.fft.rfftfreq(len(signal), 1 / SR)
    transfer = np.exp(-(frequencies / cutoff) ** 6)
    return np.fft.irfft(np.fft.rfft(signal, axis=0) * transfer[:, None], n=len(signal), axis=0)


def normalize(signal, peak):
    signal = np.asarray(signal, dtype=np.float64)
    if signal.ndim == 1:
        signal = signal[:, None]
    signal = signal - signal.mean(axis=0)
    return signal * peak / max(float(np.abs(signal).max()), 1e-12)


def frequency_energy(signal, minimum):
    spectrum = np.fft.rfft(signal, axis=0)
    energy = np.abs(spectrum) ** 2
    frequencies = np.fft.rfftfreq(len(signal), 1 / SR)
    return float(energy[frequencies >= minimum].sum() / max(energy.sum(), 1e-30))


def write_wav(path, signal, looping=False):
    signal = np.asarray(signal, dtype=np.float64)
    if signal.ndim == 1:
        signal = signal[:, None]
    assert np.isfinite(signal).all()
    assert float(np.abs(signal).max()) < .99
    pcm = np.round(signal * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(signal.shape[1])
        output.setsampwidth(2)
        output.setframerate(SR)
        output.writeframes(pcm.tobytes())
    with wave.open(str(path), "rb") as check:
        assert check.getnframes() == len(signal)
        assert check.getframerate() == SR
        assert check.getnchannels() == signal.shape[1]
        restored = np.frombuffer(check.readframes(check.getnframes()), dtype="<i2").reshape(signal.shape)
    assert np.array_equal(restored, pcm)
    decoded = restored.astype(np.float64) / 32767
    jumps = np.abs(np.diff(decoded, axis=0))
    boundary_jump = float(np.abs(decoded[0] - decoded[-1]).max())
    interior_p999 = float(np.quantile(jumps, .999))
    checks = {
        "file": str(path.relative_to(ROOT)).replace("\\", "/"),
        "seconds": round(len(signal) / SR, 4),
        "sample_rate": SR,
        "sample_frames": len(signal),
        "channels": signal.shape[1],
        "bit_depth": 16,
        "peak_dbfs": round(20 * np.log10(np.abs(decoded).max()), 2),
        "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(decoded ** 2))), 2),
        "finite": True,
        "clipped_samples": int((np.abs(restored.astype(np.int32)) >= 32767).sum()),
        "energy_above_2500_hz_percent": round(100 * frequency_energy(decoded, 2500), 5),
        "seam_adjacent_sample_jump": round(boundary_jump, 7),
        "interior_adjacent_jump_p999": round(interior_p999, 7),
        "loop": looping,
    }
    if looping:
        # A seamless waveform need not have identical endpoint samples; they
        # are consecutive moments, not duplicates. Require its seam derivative
        # to be no more abrupt than the interior signal's normal upper range.
        assert boundary_jump < interior_p999, checks
        checks.update({"loop_begin": 0, "loop_end": len(signal), "loop_mode": "forward"})
    return checks


# Eight original 4/4 bars, 80 BPM. Notes spilling beyond the last bar wrap
# into the opening, including reverb/reflection tails: a real continuous loop.
beat = .75
duration = 24
music = np.zeros((round(duration * SR), 2))
chords = [[48, 55, 59, 64], [45, 52, 55, 59], [41, 48, 52, 57], [43, 50, 55, 57]]
melodies = [[72, 76, 79, 74], [76, 71, 69, 74], [72, 76, 69, 67], [69, 74, 71, 72],
            [72, 79, 76, 74], [71, 76, 74, 69], [69, 72, 76, 72], [74, 71, 69, 67]]
for bar in range(8):
    chord = chords[bar % 4]
    at = bar * 4 * beat
    for j, midi in enumerate(chord):
        add_circular(music, note(midi, 4.15, pad=True), at - .3, .026, [-.22, .22, -.1, .1][j])
    for j, midi in enumerate([chord[0] + 12, chord[2] + 12, chord[1] + 12, chord[3] + 12]):
        add_circular(music, note(midi, 2.5), at + j * beat + .025, .060, [-.17, .18, -.1, .15][j])
    for j, midi in enumerate(melodies[bar]):
        add_circular(music, note(midi, 2.7), at + (j + .5) * beat, .061, [-.1, .08, -.06, .1][j])
dry = music.copy()
for delay, gain in [(.137, .055), (.293, .040), (.467, .028), (.719, .017)]:
    music += np.roll(dry[:, ::-1], round(delay * SR), axis=0) * gain
music = normalize(circular_lowpass(music, 3100), .27)


def periodic_noise(seconds, low, high):
    n = round(seconds * SR)
    frequencies = np.fft.rfftfreq(n, 1 / SR)
    spectrum = np.fft.rfft(RNG.normal(size=n))
    transfer = (1 - np.exp(-(frequencies / low) ** 4)) * np.exp(-(frequencies / high) ** 6)
    signal = np.fft.irfft(spectrum * transfer, n=n)
    return signal / max(float(np.std(signal)), 1e-12)


# Restrained continuous textile friction. No isolated pops or gritty grains.
# Randomized noise is rendered with circular filtering, so its spectrum and
# slow envelope repeat continuously without a splice or silence at the seam.
loop_seconds = 4
t = np.arange(round(loop_seconds * SR)) / SR
body = periodic_noise(loop_seconds, 95, 740)
air = periodic_noise(loop_seconds, 650, 1450)
cloth_envelope = 1 + .045 * np.sin(2 * np.pi * t / loop_seconds) + .022 * np.sin(6 * np.pi * t / loop_seconds + .3)
fabric = normalize((body * .94 + air * .13) * cloth_envelope, .29)
soil_body = periodic_noise(loop_seconds, 170, 950)
soil_detail = periodic_noise(loop_seconds, 600, 1800)
soil_envelope = 1 + .06 * np.sin(4 * np.pi * t / loop_seconds + 1.3)
soil = normalize((soil_body * .75 + soil_detail * .16) * soil_envelope, .23)

# A short, warm three-note resolution. Smooth attacks and releases are baked
# in; no noise, metallic partials, or runtime synthesis. The final tone ends
# before the clip boundary so this one-shot can stop without an audible cut.
completion_seconds = .84
completion = np.zeros((round(completion_seconds * SR), 1))
for midi, start, length, gain in [(72, .015, .68, .58), (76, .095, .67, .40), (79, .18, .63, .32)]:
    tone_t = np.arange(round(length * SR)) / SR
    frequency = 440 * 2 ** ((midi - 69) / 12)
    phase = 2 * np.pi * frequency * tone_t
    tone = (np.sin(phase) + .035 * np.sin(2 * phase)) * fade_curve(tone_t, .07, .28, length)
    tone *= np.exp(-tone_t / .44) * gain
    at = round(start * SR)
    completion[at:at + len(tone), 0] += tone
# Keep actual silence at each end: unlike the loop sources, do not subtract
# a global DC mean from the empty endpoints.
completion *= .18 / float(np.abs(completion).max())

metadata = [write_wav(ASSETS / "quiet_shop_music_loop.wav", music, True),
            write_wav(ASSETS / "brush_fabric_loop.wav", fabric, True),
            write_wav(ASSETS / "brush_soil_loop.wav", soil, True)]
completion_metadata = write_wav(ASSETS / "restoration_complete.wav", completion)

# An audition ending is intentionally different from the runtime loop. It
# offers a comfortable beginning and end, preserving the seamless asset.
music_audition = music[:round(14 * SR)].copy()
music_t = np.arange(len(music_audition)) / SR
music_audition *= fade_curve(music_t, .3, 1.2, 14)[:, None]
metadata.append(write_wav(AUDITIONS / "quiet_shop_music_v2_audition.wav", music_audition))

brush_audition = np.zeros((round(9.1 * SR), 1))
for stroke, dirt in enumerate([1., .82, .60, .35, .12, 0.]):
    seconds = .94
    n = round(seconds * SR)
    time = np.arange(n) / SR
    envelope = np.sin(np.pi * time / seconds) ** 1.4
    start_in_loop = round((stroke * .61) * SR)
    indices = (np.arange(n) + start_in_loop) % len(fabric)
    # Fixed source gains across all six strokes make the transition judgeable.
    sound = fabric[indices] * .75 + soil[indices] * dirt * .33
    sound *= envelope[:, None]
    at = round((.32 + stroke * 1.42) * SR)
    brush_audition[at:at + n] += sound
metadata.append(write_wav(AUDITIONS / "brush_dirty_to_clean_v2_audition.wav", brush_audition))

manifest = {
    "version": 2,
    "purpose": "Smoother original runtime loop candidates plus standalone auditions; device listening and final mix remain necessary",
    "provenance": "Original offline additive composition and filtered-noise synthesis. No downloaded samples, external recordings, or external generation model.",
    "generator": "tools/synthesize_game_audio.py",
    "changes": ["Softer raised-cosine music attacks and exact quiet harmonics", "No discrete brush ticks", "Lower brush high-frequency cutoff", "Circular note tails, reflections, and noise filtering for seamless runtime loops"],
    "listening_status": "Signal and file checks completed; not independently listened to by the generator",
    "files": metadata,
}
(AUDITIONS / "audio_manifest_v2.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
(AUDITIONS / "completion_cue_manifest.json").write_text(json.dumps({
    "purpose": "Restrained one-shot for the full-restoration reveal; not early finish",
    "provenance": manifest["provenance"],
    "generator": manifest["generator"],
    "listening_status": manifest["listening_status"],
    "files": [completion_metadata],
}, indent=2) + "\n", encoding="utf-8")
print(json.dumps(metadata, indent=2))
print(json.dumps(completion_metadata, indent=2))
