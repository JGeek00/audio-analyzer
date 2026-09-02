# Mixxx BPM core

This directory contains the independent `qm-tempotracker:0` analysis path described in [`MIXXX_BPM_ANALYSIS.md`](../../../../../MIXXX_BPM_ANALYSIS.md), based on the upstream [Mixxx source repository](https://github.com/mixxxdj/mixxx):

```text
interleaved stereo PCM
  → Mixxx-compatible downmix, overlap, and padding
  → QM-DSP DetectionFunction (DF_COMPLEXSD)
  → QM-DSP TempoTrackV2
  → BeatPostProcessor (constant regions, snapping, and phase)
  → BPM, first frame, and raw beats
```

`MixxxBpmAnalyzer` is single-use per file. `process()` accepts only interleaved stereo float32 PCM and `finish()` finalizes the padding, tempo tracking, and fixed-tempo post-processing exactly once.

The `Vendor/qm-dsp` tree contains the required upstream QM-DSP/KissFFT subset. Keep the upstream source links and license information in `Documentation/THIRD_PARTY_NOTICES.md` when preparing a distributable source tree.
