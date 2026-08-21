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
        }
    }
}

#Preview {
    MainView()
        .environmentObject(CompletionStore())
        .environmentObject(StretchStore())
        .environmentObject(RenameStore())
}
