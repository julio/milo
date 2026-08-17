import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "checklist")
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
