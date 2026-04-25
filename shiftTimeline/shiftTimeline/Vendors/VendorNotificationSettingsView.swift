import SwiftUI
import SwiftData
import TipKit
import Models

struct NotificationThresholdTip: Tip {
    var title: Text {
        Text("Customize Your Alert Sensitivity")
    }

    var message: Text? {
        Text("Adjust how much the timeline must shift before you get a notification. Small changes sync silently in the background.")
    }

    var image: Image? {
        Image(systemName: "bell.badge")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

/// Lets a vendor adjust their notification threshold — the minimum shift
/// delta (in minutes) required to trigger a visible push notification.
///
/// Shifts below the threshold still sync silently in the background.
struct VendorNotificationSettingsView: View {

    @Bindable var vendor: VendorModel

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

    private let thresholdTip = NotificationThresholdTip()

    var body: some View {
        Form {
            Section {
                TipView(thresholdTip)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notification Threshold")
                        .font(.headline)
                    Text("You'll only be notified when the timeline shifts by more than \(Int(thresholdMinutes.wrappedValue)) minutes. Smaller shifts will sync silently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)

                HStack {
                    Text("\(Int(thresholdMinutes.wrappedValue)) minutes", tableName: "Localizable", comment: "Notification threshold in minutes")
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
