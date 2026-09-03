import SwiftUI

struct MetadataValueView<Value>: View {
    let persistedValue: Value?
    let calculatedValue: Value?
    let hasConflict: Bool
    let format: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            if hasConflict, let persistedValue {
                Text(format(persistedValue))
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            if let calculatedValue {
                Text(format(calculatedValue))
            } else {
                Text("—")
            }
        }
    }
}
