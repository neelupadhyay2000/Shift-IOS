//
//  Item.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
