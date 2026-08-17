import SwiftUI

struct StretchesView: View {
    @EnvironmentObject var stretchStore: StretchStore
    @State private var selectedDate = Date()

    private var dateKey: String { StretchPlan.dateKey(for: selectedDate) }
    private var doneCount: Int { stretchStore.doneCount(dateKey: dateKey) }
    private var total: Int { StretchPlan.stretches.count }
    private var isActive: Bool { StretchPlan.isActive(on: selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let message = stretchStore.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if isActive {
                        VStack(spacing: 10) {
                            ForEach(StretchPlan.stretches.indices, id: \.self) { index in
                                StretchRow(
                                    name: StretchPlan.stretches[index],
                                    isDone: stretchStore.isDone(dateKey: dateKey, index: index)
                                ) {
                                    Task {
                                        await stretchStore.toggle(dateKey: dateKey, index: index)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Routine starts August 16, 2026")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Stretches")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                navigationBar
            }
            .task {
                await stretchStore.refresh()
            }
            .refreshable {
                await stretchStore.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title2.bold())
            Text("Daily PT routine")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
            if isActive {
                HStack {
                    Text("Every day, leg rehab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(doneCount)/\(total) done")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(doneCount == total ? .green : .secondary)
                }
                ProgressView(value: Double(doneCount), total: Double(total))
                    .tint(doneCount == total ? .green : .accentColor)
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            Button {
                withAnimation {
                    selectedDate = Calendar.current.date(
                        byAdding: .day, value: -1, to: selectedDate)!
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 34))
            }

            Spacer()

            Button("Today") {
                withAnimation { selectedDate = Date() }
            }
            .font(.caption.weight(.semibold))

            Spacer()

            Button {
                withAnimation {
                    selectedDate = Calendar.current.date(
                        byAdding: .day, value: 1, to: selectedDate)!
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 34))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct StretchRow: View {
    let name: String
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isDone ? .green : .secondary)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .strikethrough(isDone)
            Spacer()
        }
        .padding(12)
        .background(isDone ? Color.green.opacity(0.12) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

#Preview {
    StretchesView()
        .environmentObject(StretchStore())
}
