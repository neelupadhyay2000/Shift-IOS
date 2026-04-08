//
//  shiftTimelineWidgetBundle.swift
//  shiftTimelineWidget
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import WidgetKit
import SwiftUI

@main
struct shiftTimelineWidgetBundle: WidgetBundle {
    var body: some Widget {
        shiftTimelineWidget()
        shiftTimelineWidgetControl()
        ShiftLiveActivity()
    }
}
