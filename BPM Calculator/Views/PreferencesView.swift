import SwiftUI

struct PreferencesView: View {
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue

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
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 300)
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
