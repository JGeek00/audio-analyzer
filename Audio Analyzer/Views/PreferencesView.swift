import SwiftUI

struct PreferencesView: View {
    @AppStorage(AppStorageKeys.appTheme) private var theme = AppConfiguration.defaultTheme.rawValue
    @AppStorage(AppStorageKeys.waveformDimming) private var waveformDimming = AppConfiguration.defaultWaveformDimming.rawValue
    @AppStorage(AppStorageKeys.showBeatMarkers) private var showBeatMarkers = AppConfiguration.defaultShowBeatMarkers
    @AppStorage(AppStorageKeys.lowPerformanceMode) private var lowPerformanceMode = AppConfiguration.defaultLowPerformanceMode
    @AppStorage(AppStorageKeys.autoSave) private var autoSave = AppConfiguration.defaultAutoSave
    @AppStorage(AppStorageKeys.replayGainTargetLUFS) private var targetLUFS =
        AppConfiguration.defaultReplayGainTargetLUFS
    @AppStorage(AppStorageKeys.replayGainClipMode) private var clipMode =
        AppConfiguration.defaultReplayGainClipMode.rawValue
    @AppStorage(AppStorageKeys.replayGainMaxPeakDB) private var maxPeakDB =
        AppConfiguration.defaultReplayGainMaxPeakDB
    @AppStorage(AppStorageKeys.opusGainMode) private var opusMode =
        AppConfiguration.defaultOpusGainMode.rawValue
    @AppStorage(AppStorageKeys.opusForce23) private var opusForce23 =
        AppConfiguration.defaultOpusForce23

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? AppConfiguration.defaultTheme
    }

    private var selectedClipMode: ReplayGainClipMode {
        ReplayGainClipMode(rawValue: clipMode) ?? AppConfiguration.defaultReplayGainClipMode
    }

    private var opusUsesR128: Bool {
        (OpusGainMode(rawValue: opusMode) ?? AppConfiguration.defaultOpusGainMode).usesR128
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("Auto save", isOn: $autoSave)
                    .help("Automatically saves calculated and manually adjusted BPM values to metadata.")
            } header: {
                Text("General")
            } footer: {
                Text("Automatically saves calculated BPM after analysis and manually adjusted BPM after each change.")
            }

            Section {
                Picker("Dimmed section", selection: $waveformDimming) {
                    ForEach(WaveformDimming.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("Show beat markers", isOn: $showBeatMarkers)

                Toggle("Low performance mode", isOn: $lowPerformanceMode)
                    .help("Reduces waveform resolution and playback refresh rate.")
            } header: {
                Text("Waveform")
            } footer: {
                Text("Low performance mode reduces waveform resolution and refresh rate to improve performance on less powerful Macs.")
            }

            Section {
                HStack(spacing: 4) {
                    Text("Target loudness")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField(
                        "",
                        value: $targetLUFS,
                        format: .number.precision(.fractionLength(0))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    Stepper("", value: $targetLUFS, in: (-30)...(-6), step: 1)
                        .labelsHidden()
                    Text("LUFS")
                        .foregroundStyle(.secondary)
                }
                .help("Reference loudness. Each track's gain is target minus measured loudness. −18 LUFS matches classic ReplayGain; streaming services use −14 to −16.")

                Picker("Clipping protection", selection: $clipMode) {
                    ForEach(ReplayGainClipMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .help("Lowers the calculated gain when applying it would push peaks over Max Peak. Positive-only protects loud tracks without touching quiet ones.")

                HStack(spacing: 4) {
                    Text("Max Peak")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField(
                        "",
                        value: $maxPeakDB,
                        format: .number.precision(.fractionLength(1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .disabled(selectedClipMode == .disabled)
                    Stepper("", value: $maxPeakDB, in: (-12)...0, step: 0.5)
                        .labelsHidden()
                        .disabled(selectedClipMode == .disabled)
                    Text("dB")
                        .foregroundStyle(.secondary)
                }
                .help("Ceiling used by clipping protection. 0 dB is digital full scale.")
            } header: {
                Text("ReplayGain")
            } footer: {
                Text("Gain is applied by the player at playback time. Changing these values updates the ReplayGain column instantly, without re-analyzing.")
            }

            Section {
                Picker("Opus files", selection: $opusMode) {
                    ForEach(OpusGainMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .help("Which tag names to write for .opus files. R128_*_GAIN follows RFC 7845.")

                Toggle("Always reference Opus R128 tags to −23 LUFS", isOn: $opusForce23)
                    .disabled(!opusUsesR128)
                    .help("Compute Opus R128 gains against −23 LUFS instead of the target loudness above.")
            } header: {
                Text("Opus")
            } footer: {
                Text("Standard tags keep Opus files consistent with the rest of the library; R128 tags follow the Opus spec.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 680)
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
