import SwiftUI

@main
struct WorkoutTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(CompletionStore())
                .environmentObject(StretchStore())
                .environmentObject(RenameStore())
                .environmentObject(LogStore())
                .environmentObject(SyncEngine.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SyncEngine.shared.flush() }
            }
        }
    }
}
