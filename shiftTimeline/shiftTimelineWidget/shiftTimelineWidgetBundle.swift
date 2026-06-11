import WidgetKit
import SwiftUI
import Models

@main
struct shiftTimelineWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftSmallWidget()
        ShiftMediumWidget()
        ShiftLiveActivity()
    }
}
