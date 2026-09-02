# Analysis services

The service receives a user-selected file, decodes it with `AVAudioFile`/`AVAudioConverter` into interleaved stereo float32 PCM, and feeds one independent analyzer instance per track.

```text
fileImporter
  → TrackAnalysisService (OperationQueue: max(1, CPU/2))
  → AudioFileDecoder (4096-frame blocks, source sample rate preserved)
  → MixxxBPMAnalyzerBridge
  → MixxxBpmAnalyzer
  → BPMAnalysisResult
```

The core uses the upstream [Mixxx](https://github.com/mixxxdj/mixxx) `qm-tempotracker:0` path with `fixedTempo=true` and `fastAnalysis=false`. It does not reuse previous analysis, write tags, or modify the source file.
