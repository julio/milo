import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "checklist")
                }
            ProgressTabView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(CompletionStore())
        .environmentObject(StretchStore())
        .environmentObject(RenameStore())
        .environmentObject(LogStore())
}
