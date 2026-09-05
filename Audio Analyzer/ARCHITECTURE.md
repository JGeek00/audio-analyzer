# Architecture and development guide

Audio Analyzer is a macOS SwiftUI application with a small Objective-C++
boundary to a C++ BPM-analysis core. The code is organized by responsibility,
not by framework layer alone.

## Directory map

The diagram intentionally shows directories, not every file in the project.

```text
audio-analyzer/
├── Audio Analyzer/                 # Application source and bundled resources
│   ├── App/                         # App composition, window lifecycle, shared state
│   ├── Enums/                       # Small domain and presentation enums/errors
│   ├── Features/                    # User-facing feature areas
│   │   ├── Workspace/               # Main workspace and file import
│   │   ├── TrackList/               # Imported-track table and track actions
│   │   └── Waveform/                # Waveform, playback, seeking, and beat markers
│   ├── Models/                      # SwiftUI-independent domain values
│   ├── Services/                    # I/O, decoding, and analysis operations
│   │   ├── Audio/                   # Audio decoding, waveform extraction, metadata I/O
│   │   └── Analysis/                # Analysis orchestration and language bridge
│   │       └── Core/                # Standalone C++ BPM and key algorithms
│   │           └── Vendor/           # Upstream third-party source and licenses
│   │               └── qm-dsp/       # QM-DSP onset, tempo, and key subset
│   │                   └── ext/     # Dependencies bundled by QM-DSP
│   │                       └── kissfft/ # FFT implementation used by QM-DSP
│   ├── Views/                       # App-level settings and other shared views
│   └── Assets.xcassets/             # App icons and asset catalog
├── ReadmeAssets/                    # Images used by the repository README
└── Audio Analyzer.xcodeproj/        # Xcode project, target, and build settings
```

The repository root also contains documentation and project metadata. Keep
user-facing project information in `README.md`, licensing in `LICENSE.md`,
third-party attribution in `THIRD_PARTY_NOTICES.md`, and ignore rules in
`.gitignore`. The `Audio Analyzer` directory contains the technical
architecture and third-party notices that ship with the source tree.

### Directory ownership

- **`App/`** owns composition and application lifecycle. It creates the shared
  `WorkspaceModel`, configures the main window and commands, and handles window
  close warnings. It is the right place for application-wide state, not for
  feature-specific rendering.
- **`Enums/`** contains small shared enums and user-facing error types. Put a
  type here when it is shared by multiple areas and is not itself a model or a
  view.
- **`Features/`** contains UI grouped by user capability. Feature views render
  state and emit user intent through bindings or closures. They should not own
  workspace-wide business rules or the BPM algorithm.
- **`Models/`** contains values such as tracks and analysis results. Models do
  not import SwiftUI and should remain safe to pass across asynchronous work.
- **`Services/Audio/`** is the boundary with AVFoundation for reading audio,
  extracting waveform data, reading metadata, and writing BPM metadata.
- **`Services/Analysis/`** coordinates file analysis and exposes the
  Objective-C++ bridge used by Swift. It keeps scheduling and file I/O outside
  the algorithm.
- **`Services/Analysis/Core/`** is the platform-independent C++ analysis core.
  It must not depend on SwiftUI, AppKit, workspace state, or view code.
- **`Services/Analysis/Core/Vendor/`** is reserved for upstream-derived code
  and its license files. Do not mix application-specific Swift or C++ helpers
  into this directory.
- **`Views/`** contains app-level views such as Preferences. A view belongs
  here when it is shared by the app rather than tied to one feature.
- **`Assets.xcassets/`** contains visual resources managed by Xcode, not
  runtime code.
- **`ReadmeAssets/`** contains documentation images only; it is not an app
  resource directory.

## Runtime flow

### Import and analysis

```text
file picker / drag and drop
        ↓
WorkspaceModel.importTracks(from:)
        ↓ validates audio URLs and removes duplicates
        ├── AudioFileDecoder.metadata(for:)
        └── TrackAnalysisService.analyze(url:)
                ↓
        AudioFileDecoder / AVAudioConverter
                ↓ source-rate, interleaved stereo float32 PCM
         MixxxBPMAnalyzerBridge
                 ↓
         MixxxBpmAnalyzer + MixxxKeyAnalyzer (QM-DSP)
                 ↓
         BPMAnalysisResult + KeyAnalysisResult
                ↓
        WorkspaceModel → TrackListView / WaveformView
```

The workspace model is the coordinator for imported tracks, selection, status,
manual BPM changes, and metadata saves. Views receive the resulting state and
send actions back to the model.

### Waveform and playback

When a track is selected, `WaveformView` loads waveform peaks through the audio
decoder and creates a `WaveformAudioPlayer` for playback. `WaveformEditorView`
composes the zoomed view, overview, controls, and progress. `WaveformCanvas`
does the drawing and exposes a slider-based accessibility representation.

The selected track's raw beat frames are converted to normalized positions for
display. Playback is independent from BPM analysis; neither operation should
be made a prerequisite for the other.

### Metadata

Metadata is read when a track is imported. Saving is explicit: the metadata
writer preserves existing metadata and replaces only the selected BPM and/or
key items, then safely replaces the original file. A calculated or manually
adjusted BPM is considered unsaved until that operation succeeds.

Key values use the container's native field: `TKEY` in ID3 (MP3, AIFF, and
RIFF/WAV), `----:com.apple.iTunes:initialkey` in MP4/M4A, and `KEY`
in Vorbis comments (FLAC, OGG, and Opus).

## General code conventions

### Structure and naming

- Use one primary type per source file when practical, and name the file after
  that type.
- Use `UpperCamelCase` for types and `lowerCamelCase` for methods and
  properties. Preserve established technical initialisms such as `BPM`, `URL`,
  `PCM`, `DSP`, and `AV`.
- Keep directories named after responsibilities and group a new feature under
  `Features/<FeatureName>/` rather than adding unrelated views to an existing
  feature.
- Prefer the existing concrete types and services. Do not add a protocol,
  factory, coordinator, or dependency for a single implementation without a
  demonstrated need.
- Prefer native Swift, SwiftUI, AppKit, and AVFoundation APIs. The project has
  no third-party Swift package dependency.

### Swift style

- Use four-space indentation, braces on the same line, and the existing Xcode
  formatting style for multiline calls and declarations.
- Prefer early exits with `guard` for invalid input and unavailable state.
- Keep view-only formatting and small helper calculations private to the view.
  Shared domain rules belong in a model, enum, or service.
- Keep SwiftUI views as value types. Use `@State` for view-local transient
  state, `@Binding` for state owned by a parent, and closures for actions that
  must be handled by a parent or model.
- Use `@Observable` and `@MainActor` for shared mutable UI state, as with
  `WorkspaceModel`. Avoid global mutable state.
- Keep models independent from SwiftUI. Values crossing task boundaries should
  be `Sendable` where appropriate.
- Use computed properties for derived presentation values instead of storing
  duplicate state.
- Use `LocalizedError` for errors that can reach the UI, with a stable error
  case and a concise `errorDescription`.
- Use native controls and preserve accessibility support. Interactive custom
  drawing should provide an accessibility equivalent, labels, and help text
  where the existing UI does so.
- Store user preferences with `@AppStorage`. Add a key in `AppStorageKeys`, a
  default in `AppConfiguration`, and the corresponding control in
  `PreferencesView`; if the setting affects the main window, apply it there as
  well.

### Concurrency and file access

- UI state is main-actor isolated. Do not update models or views directly from
  background work.
- Keep blocking audio decoding and analysis off the main actor. Waveform work
  uses detached work and track analysis uses an `OperationQueue` limited to
  `max(1, CPU / 2)` operations.
- Use task cancellation checks for new long-running asynchronous operations and
  avoid retaining the workspace unnecessarily from tasks.
- Every user-selected security-scoped URL must balance
  `startAccessingSecurityScopedResource()` with
  `stopAccessingSecurityScopedResource()`, normally using `defer`.
- Validate file URLs and audio types at the import boundary. Only MP3, FLAC,
  ALAC (M4A), OGG, Opus, and WAV are supported (`AppConfiguration`
  is the single source of truth); anything else is rejected with an
  unsupported-format alert. Deduplicate using
  standardized, symlink-resolved paths before creating track state.
- Propagate failures to the model and present them through the existing alert
  pattern. Do not silently convert a failed analysis into a successful result.

## Adding a new feature

1. **Define the state and owner first.** Decide whether the state is transient
   view state, selected-track state, or workspace-wide state. Put it in the
   smallest appropriate owner; shared state belongs in `WorkspaceModel`.
2. **Choose the directory by responsibility.** Add feature UI under
   `Features/<FeatureName>/`; reusable domain values under `Models/` or
   `Enums/`; file or platform operations under the appropriate service.
3. **Keep the data flow one-way.** The model/service produces state, the view
   renders it, and user actions travel back through a binding or callback. Do
   not make a child view mutate a sibling or reach into workspace internals.
4. **Reuse existing services.** Extend `AudioFileDecoder`,
   `AudioMetadataWriter`, or `TrackAnalysisService` when the new behavior is
   part of an existing boundary. Do not duplicate AVFoundation setup in a new
   feature.
5. **Handle all UI states.** Consider empty, loading/queued, completed, failed,
   unavailable, and cancellation states. Keep destructive or data-loss actions
   behind the existing confirmation pattern.
6. **Preserve file safety.** Metadata changes must be explicit, preserve all
   unrelated metadata, and use security-scoped access for imported files.
7. **Add preferences consistently.** Follow the `AppStorageKeys` →
   `AppConfiguration` → `PreferencesView` path rather than introducing a
   second settings mechanism.
8. **Add accessibility with the feature.** Label custom controls, provide
   keyboard support when appropriate, and expose an equivalent native control
   for custom-drawn interactions.
9. **Keep the diff focused.** Do not reorganize unrelated directories or
   introduce abstractions for hypothetical future requirements.
10. **Validate the user flow.** Build the **Audio Analyzer** scheme and manually
    exercise the new flow with valid, invalid, empty, and repeated inputs as
    applicable. SwiftUI previews are useful for view-only changes. The project
    currently has no test target, so build and focused manual checks are the
    existing baseline.

## BPM analysis constraints

The C++ core follows the upstream Mixxx `qm-tempotracker:0` path. These details
are part of the result and must not be changed casually:

- Preserve the source sample rate and pass interleaved stereo float32 PCM.
- Use one analyzer instance per track and call `finish()` exactly once.
- Preserve the 4096-frame decoding blocks, downmix, overlap, leading/trailing
  padding, detection-function settings, and Mixxx post-processing.
- Preserve the truncating step-size calculation, integer half-step offset,
  constant-region processing, phase adjustment, and BPM snapping behavior.
- Keep the C++ core independent from scheduling, file I/O, and UI. Adapt types
  at the Objective-C++ bridge rather than leaking Swift or AppKit concerns into
  the algorithm.
- Preserve upstream copyright headers and license files when modifying or
  moving vendored QM-DSP/KissFFT code. Update the third-party notices when
  adding another upstream-derived component.

## Current boundaries

The current implementation intentionally does not provide persistent analysis
or caching, stem-specific semantics, the legacy SoundTouch analyzer, or a
variable-tempo beat-grid UI. Key detection follows Mixxx's default
`qm-keydetector:2` path and is calculated alongside BPM from the same decoded
PCM stream; its result can be explicitly persisted as the file's ID3 initial-key
metadata alongside BPM.
