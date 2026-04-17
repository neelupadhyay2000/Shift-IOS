import SwiftUI
import Models
import SwiftData

/// Lets a vendor adjust their notification threshold — the minimum shift
/// delta (in minutes) required to trigger a visible push notification.
///
/// Shifts below the threshold still sync silently in the background.
struct VendorNotificationSettingsView: View {

    @Bindable var vendor: VendorModel
    @Environment(\.modelContext) private var modelContext

    /// Threshold in minutes, backed by the model's `TimeInterval` (seconds).
    private var thresholdMinutes: Binding<Double> {
        Binding(
            get: { vendor.notificationThreshold / 60 },
            set: { vendor.notificationThreshold = $0 * 60 }
        )
    }

    private static let presets: [(label: String, minutes: Double)] = [
        ("5 min", 5),
        ("10 min", 10),
        ("15 min", 15),
        ("30 min", 30),
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notification Threshold")
                        .font(.headline)
                    Text("You'll only receive a visible notification when the timeline shifts by at least this amount. Smaller shifts sync silently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)

                HStack {
                    Text("\(Int(thresholdMinutes.wrappedValue)) minutes")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                    Spacer()
                }

                Slider(
                    value: thresholdMinutes,
                    in: 1...60,
                    step: 1
                ) {
                    Text("Threshold")
                } minimumValueLabel: {
                    Text("1")
                        .font(.caption2)
                } maximumValueLabel: {
                    Text("60")
                        .font(.caption2)
                }

                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.minutes) { preset in
                        Button(preset.label) {
                            withAnimation {
                                thresholdMinutes.wrappedValue = preset.minutes
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            Int(thresholdMinutes.wrappedValue) == Int(preset.minutes)
                                ? .accentColor : .secondary
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
