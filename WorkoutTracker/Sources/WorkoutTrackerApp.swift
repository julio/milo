import SwiftUI

@main
struct WorkoutTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(CompletionStore())
                .environmentObject(StretchStore())
                .environmentObject(RenameStore())
        }
    }
}
