# Architecture

The application is organized by responsibility:

```text
BPM Calculator/
├── App/                    # App composition, window scenes, and shared state
│   ├── BPMCalculatorApp.swift       # Root app and scene declarations
│   ├── MainWindowScene.swift        # Main window and app commands
│   ├── MainWindowAccessor.swift     # AppKit window access from SwiftUI
│   ├── MainWindowDelegate.swift      # Close-warning handling
│   └── WorkspaceModel.swift         # Shared workspace state
├── Enums/                  # Shared presentation and domain enums
│   ├── AppTheme.swift      # Supported appearance modes
│   └── BPMAdjustment.swift # Supported BPM transformations
├── Views/                  # App-level SwiftUI views
│   └── PreferencesView.swift        # Settings layout and theme picker
├── Models/                 # SwiftUI-independent domain models
├── Features/
│   ├── Workspace/          # Main window layout and file import
│   ├── TrackList/          # Imported track library and selection
│   └── Waveform/           # Selected-track analysis and waveform area
├── Services/
│   ├── Audio/              # macOS audio decoding
│   └── Analysis/           # Analysis service, bridge, and BPM core
├── BPM-Calculator-Bridging-Header.h
└── Assets.xcassets
```

## Dependencies

`App` composes the application, owns the workspace state, and configures the main window. `MainWindowScene` contains the main window scene and its commands, while `MainWindowDelegate` and `MainWindowAccessor` keep AppKit window behavior separate from scene composition. `Views` contains app-level SwiftUI views such as the settings screen. `Features` receive state and models; they do not know about decoding or DSP. `Models` do not depend on SwiftUI. Audio decoding and BPM analysis live in `Services` and are consumed by the workspace model through concrete operations.

`AppTheme` defines the three supported appearance modes (`system`, `light`, and `dark`) and maps them to SwiftUI color schemes. `PreferencesView` persists the selected mode with `AppStorage`; `MainWindowScene` observes the same preference so the main window and settings use the selected theme.

`TrackListView` exposes BPM transformations in a contextual submenu once a track has finished processing. `WorkspaceModel.adjustBPM(for:using:)` replaces the calculated BPM while preserving the rest of the analysis result, so the table and metadata-saving flow use the adjusted value. The BPM column marks tracks whose calculated value differs from metadata, unless the value was manually adjusted, and marks manual adjustments separately. Both indicators provide explanatory tooltips. `WorkspaceView` provides a clear-tracks action and asks for confirmation when there are unsaved BPM values.

## Mixxx-compatible analysis

The implementation follows the upstream [Mixxx repository](https://github.com/mixxxdj/mixxx) and the decisions recorded in [`MIXXX_BPM_ANALYSIS.md`](../../MIXXX_BPM_ANALYSIS.md). The current flow is:

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

The vendored QM-DSP/KissFFT subset and third-party licensing information are documented in `Services/Analysis/Core/MixxxBpmAnalyzer.md` and `THIRD_PARTY_NOTICES.md`. Metadata exports preserve the existing metadata and replace only the BPM item; they use an item-replacement directory on the source file's volume so sandboxed writes can safely replace the original file. Persistence, caching, key detection, and variable-tempo UI remain separate follow-up work.
