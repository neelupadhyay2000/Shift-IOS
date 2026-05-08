import SwiftUI

/// A Form-compatible date/time picker row with a trailing checkmark button.
///
/// The picker stays open until the user explicitly taps the checkmark, which recycles the view identity to dismiss the popover. There is no auto-close
/// on value change — the selection is only committed on confirm.
struct DatePickerRow: View {

    let label: String
    let components: DatePickerComponents
    @Binding var selection: Date

    @State private var pickerID = UUID()

    init(_ label: String, selection: Binding<Date>, components: DatePickerComponents) {
        self.label = label
        self.components = components
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            DatePicker(label, selection: $selection, displayedComponents: components)
                .id(pickerID)

            // Confirm button — the only way to dismiss the picker popover.
            // Recycling pickerID forces SwiftUI to tear down and rebuild the
            // DatePicker, which closes any open popover.
            Button {
                pickerID = UUID()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .accessibilityLabel(String(localized: "Confirm selection"))
        }
    }
}
