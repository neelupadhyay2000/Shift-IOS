import TipKit

// MARK: - Add Block

/// Surfaces after the first event is created. Teaches the + button in TimelineBuilderView.
struct AddBlockTip: Tip {
    var title: Text {
        Text("Add Your First Block")
    }

    var message: Text? {
        Text("Tap the + button to create a time block for your event.")
    }

    var image: Image? {
        Image(systemName: "plus.circle")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

// MARK: - Reorder Block

/// Surfaces in the timeline builder. Teaches the long-press drag gesture.
struct ReorderBlockTip: Tip {
    var title: Text {
        Text("Drag to Reorder")
    }

    var message: Text? {
        Text("Long-press any block to drag and reorder it in your timeline.")
    }

    var image: Image? {
        Image(systemName: "line.3.horizontal")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

// MARK: - Pinned Block

/// Surfaces when a pinned block is present. Teaches pinning semantics.
struct PinnedBlockTip: Tip {
    var title: Text {
        Text("Pinned Blocks Stay Put")
    }

    var message: Text? {
        Text("Pinned blocks are anchored in time and won't move when you shift the timeline.")
    }

    var image: Image? {
        Image(systemName: "pin.fill")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

// MARK: - Shift Timeline

/// Surfaces the first time the user enters live mode. Teaches the Quick Shift button.
struct ShiftTimelineTip: Tip {
    var title: Text {
        Text("Shift the Timeline")
    }

    var message: Text? {
        Text("Tap the clock icon to push all upcoming blocks forward or backward when you're running late.")
    }

    var image: Image? {
        Image(systemName: "clock.arrow.circlepath")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

// MARK: - Slide to Advance

/// Surfaces on the slide-to-advance control in live mode. Teaches block completion.
struct SlideToAdvanceTip: Tip {
    var title: Text {
        Text("Complete a Block")
    }

    var message: Text? {
        Text("Slide to mark the current block complete and move on to the next one.")
    }

    var image: Image? {
        Image(systemName: "arrow.right.circle.fill")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}
