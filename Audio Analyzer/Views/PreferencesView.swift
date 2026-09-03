import SwiftUI

struct PreferencesView: View {
    @AppStorage(AppStorageKeys.appTheme) private var theme = AppConfiguration.defaultTheme.rawValue
    @AppStorage(AppStorageKeys.waveformDimming) private var waveformDimming = AppConfiguration.defaultWaveformDimming.rawValue
    @AppStorage(AppStorageKeys.showBeatMarkers) private var showBeatMarkers = AppConfiguration.defaultShowBeatMarkers
    @AppStorage(AppStorageKeys.lowPerformanceMode) private var lowPerformanceMode = AppConfiguration.defaultLowPerformanceMode
    @AppStorage(AppStorageKeys.autoSave) private var autoSave = AppConfiguration.defaultAutoSave

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? AppConfiguration.defaultTheme
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
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 420)
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
