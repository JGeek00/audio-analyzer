# Architecture

The application is organized by responsibility:

```text
BPM Calculator/
├── App/                    # App composition and shared window state
├── Models/                 # SwiftUI-independent domain models
├── Features/
│   ├── Workspace/          # Main window layout and file import
│   ├── TrackList/          # Imported track library and selection
│   └── Waveform/           # Selected-track analysis and waveform area
├── Services/
│   ├── Audio/              # macOS audio decoding
│   └── Analysis/           # Analysis service, bridge, and BPM core
├── Documentation/
└── Assets.xcassets
```

## Dependencies

`App` composes the application and owns the workspace state. `Features` receive state and models; they do not know about decoding or DSP. `Models` do not depend on SwiftUI. Audio decoding and BPM analysis live in `Services` and are consumed by the workspace model through concrete operations.

## Mixxx-compatible analysis

The implementation follows the upstream [Mixxx repository](https://github.com/mixxxdj/mixxx) and the decisions recorded in [`MIXXX_BPM_ANALYSIS.md`](../../../MIXXX_BPM_ANALYSIS.md). The current flow is:

```text
file importer
  → AVAudioFile / AVAudioConverter
  → interleaved stereo float32 PCM
  → MixxxBpmAnalyzer (QM-DSP tempo tracker)
  → BPMAnalysisResult
  → UI
```

`AudioFileDecoder` preserves the source sample rate and delivers blocks of 4096 frames. `MixxxBpmAnalyzer` uses the `qm-tempotracker:0` path with `fixedTempo=true` and `fastAnalysis=false`. Its post-processing preserves constant regions, BPM snapping, phase adjustment, and final frame rounding.

The Objective-C++ bridge exposes BPM, first beat, sample rate, and raw beat frames to Swift. `TrackAnalysisService` keeps file I/O and concurrency outside the algorithm and limits simultaneous analyses to `max(1, CPU/2)`.

The vendored QM-DSP/KissFFT subset and third-party licensing information are documented in `Services/Analysis/Core/MixxxBpmAnalyzer.md` and `Documentation/THIRD_PARTY_NOTICES.md`. Persistence, caching, key detection, variable-tempo UI, and waveform rendering remain separate follow-up work.
