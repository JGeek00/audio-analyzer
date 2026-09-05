import MarkdownUI
import SwiftUI

struct LicensesView: View {
    var body: some View {
        ScrollView {
            Group {
                Markdown(bundledText())
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("License")
        .textSelection(.enabled)
    }

    // ponytail: single English source (Views/Licenses.md), shipped in the bundle.
    private func bundledText() -> String {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return String(localized: "License text unavailable.")
        }
        return content
    }
}
