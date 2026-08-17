import SwiftUI

@main
struct WorkoutTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(WorkoutStore())
                .environmentObject(CompletionStore())
        }
    }
}
