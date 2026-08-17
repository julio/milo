import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            TrainingPlanView()
                .tabItem {
                    Label("Plan", systemImage: "dumbbell")
                }
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
            ContentView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet")
                }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(WorkoutStore())
        .environmentObject(CompletionStore())
}
