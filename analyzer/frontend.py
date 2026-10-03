"""MyMusic Semantic v2 evaluated frontend, independently vendored for HomeStereo."""
import math

def mel_spectrogram(y):
    """Independently implement the published MusiCNN frontend parameters.

    See README for the precise official references and validation limitations.
    No per-track normalization: the pretrained network expects absolute log mel.
    """
    import librosa
    import numpy as np
    if y.size < 32768:
        raise ValueError('At least 2.048 seconds are needed for a model patch')
    frame_count = 1 + math.ceil((len(y) - 256) / 256)
    padded = np.pad(y, (256, 512))
    frames = np.lib.stride_tricks.sliding_window_view(padded, 512)[::256][:frame_count]
    windowed = frames * np.hanning(512).astype(np.float32)
    power = np.abs(np.fft.rfft(windowed, axis=1)) ** 2
    filters = librosa.filters.mel(sr=16000, n_fft=512, n_mels=96, fmin=0, fmax=8000, htk=False, norm='slaney')
    return np.log10(1.0 + 10000.0 * (power @ filters.T)).astype(np.float32)

def average_channels(raw: bytes, channels: int):
    import numpy as np
    if not 1 <= channels <= 8:
        raise ValueError('PoC supports 1–8 channels')
    samples = np.frombuffer(raw, dtype='<f4')
    if samples.size % channels:
        raise ValueError('Incomplete PCM frame')
    return samples.reshape(-1, channels).mean(axis=1)

def _segment_offsets(duration: float, segment_seconds: float, segment_count: int) -> list[float]:
    segment_length = min(segment_seconds, duration)
    available = max(0.0, duration - segment_length)
    if segment_count <= 1 or available <= segment_length * 0.25:
        return [available * 0.5]
    if segment_count == 2:
        fractions = [0.15, 0.85]
    elif segment_count == 3:
        fractions = [0.1, 0.5, 0.9]
    else:
        fractions = [index / (segment_count - 1) for index in range(segment_count)]
    return [available * fraction for fraction in fractions]
