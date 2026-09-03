# Analysis services

The service receives a user-selected file, decodes it with `AVAudioFile`/`AVAudioConverter` into interleaved stereo float32 PCM, and feeds one independent analyzer instance per track.

```text
fileImporter
  → TrackAnalysisService (OperationQueue: max(1, CPU/2))
  → AudioFileDecoder (4096-frame blocks, source sample rate preserved)
  → MixxxBPMAnalyzerBridge
  → MixxxBpmAnalyzer + MixxxKeyAnalyzer + ReplayGainAnalyzer
  → BPMAnalysisResult + KeyAnalysisResult + ReplayGainResult
```

The core uses the upstream [Mixxx](https://github.com/mixxxdj/mixxx) `qm-tempotracker:0` path with `fixedTempo=true` and `fastAnalysis=false`, plus the default `qm-keydetector:2` path. Both analyzers consume the same decoded PCM blocks. It does not reuse previous analysis, write tags, or modify the source file.

ReplayGain track gain is measured in the same pass by `ReplayGainAnalyzer`, an ITU-R BS.1770 integrated-loudness implementation whose filter design follows [libebur128](https://github.com/jiixyj/libebur128) (MIT, see `Core/LIBEBUR128-LICENSE.md`).
