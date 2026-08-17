import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            TrainingPlanView()
                .tabItem {
                    Label("Plan", systemImage: "dumbbell")
                }
            StretchesView()
                .tabItem {
                    Label("Stretches", systemImage: "figure.cooldown")
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
        .environmentObject(StretchStore())
}
