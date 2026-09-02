import SwiftUI

struct PreferencesView: View {
    @AppStorage(AppStorageKeys.appTheme) private var theme = AppTheme.system.rawValue
    @AppStorage(AppStorageKeys.waveformDimming) private var waveformDimming = WaveformDimming.listened.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: theme) ?? .system
    }

    var body: some View {
        Form {
            Section("General") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Waveform") {
                Picker("Dimmed section", selection: $waveformDimming) {
                    ForEach(WaveformDimming.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 380)
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
