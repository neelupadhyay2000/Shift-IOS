//
//  ContentView.swift
//  shiftTimeline
//
//  Created by Neel Upadhyay on 2026-04-07.
//

import SwiftUI
import ActivityKit

struct ContentView: View {
    // Keep track of the active Live Activity so we can update/end it
    @State private var currentActivity: Activity<ShiftActivityAttributes>?

    var body: some View {
        VStack(spacing: 30) {
            Text("SHIFT: Command Center")
                .font(.title)
                .fontWeight(.bold)

            // 1. START BUTTON
            Button(action: {
                startActivity()
            }) {
                Text("Start Live Activity")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .padding(.horizontal, 40)

            // 2. UPDATE BUTTON
            Button(action: {
                updateActivity()
            }) {
                Text("Shift to Next Block")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .disabled(currentActivity == nil) // Disable if not running

            // 3. END BUTTON
            Button(action: {
                endActivity()
            }) {
                Text("End Event")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .disabled(currentActivity == nil)
        }
        .padding()
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ShiftActivityAttributes(eventName: "Preet's Bachelor Party")
        let contentState = ShiftActivityAttributes.ContentState(currentBlockName: "Dinner at Carbone")
        let activityContent = ActivityContent(state: contentState, staleDate: nil)

        do {
            // Save the returned activity to our state variable
            currentActivity = try Activity.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
            print("Live Activity Started!")
        } catch {
            print("Failed to start activity: \(error.localizedDescription)")
        }
    }

    private func updateActivity() {
        guard let activity = currentActivity else { return }

        // Create a new state with updated data
        let newState = ShiftActivityAttributes.ContentState(currentBlockName: "Speeches & Toasts 🎤")
        let updatedContent = ActivityContent(state: newState, staleDate: nil)

        Task {
            await activity.update(updatedContent)
            print("Live Activity Updated!")
        }
    }

    private func endActivity() {
        guard let activity = currentActivity else { return }

        // Give it a final state before it disappears from the lock screen
        let finalState = ShiftActivityAttributes.ContentState(currentBlockName: "Event Complete 🏁")
        let finalContent = ActivityContent(state: finalState, staleDate: nil)

        Task {
            // .default allows it to linger on the lock screen for a short time.
            // .immediate wipes it instantly.
            await activity.end(finalContent, dismissalPolicy: .default)
            currentActivity = nil
            print("Live Activity Ended!")
        }
    }
}

#Preview {
    ContentView()
}
