import SwiftUI

private enum EntrySheet: Identifiable {
    case feeding, diaper, edit(Activity)
    var id: String {
        switch self {
        case .feeding: return "feeding"
        case .diaper: return "diaper"
        case .edit(let activity): return activity.id.uuidString
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingProfile = false
    @State private var entrySheet: EntrySheet?
    @State private var pendingDeletion: Activity?

    var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if store.loadFailed {
                        ContentUnavailableView {
                            Label("Unable to open records", systemImage: "externaldrive.badge.exclamationmark")
                        } description: {
                            Text(store.accountChanged ? store.syncStatus : "Your saved records have been kept intact. Close and reopen the app, or try again.")
                        } actions: {
                            if !store.accountChanged { Button("Try again") { store.reload() } }
                        }
                    } else if let child = store.selectedChild {
                        dashboard(child)
                    } else {
                        ContentUnavailableView {
                            Label("Welcome to Baby Buddy", systemImage: "heart.fill")
                        } description: {
                            Text("Create your child's profile to start keeping track of the little things.")
                        } actions: {
                            Button("Create child profile") { showingProfile = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .navigationTitle("Baby Buddy")
                .toolbar {
                    if store.selectedChild != nil {
                        Button { showingProfile = true } label: { Label("Child profile", systemImage: "person.crop.circle") }
                    }
                }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                List {
                    if store.activities.isEmpty {
                        ContentUnavailableView("No activities yet", systemImage: "clock", description: Text("Your saved feedings, diapers and sleep will appear here."))
                    }
                    ForEach(store.activities) { activity in
                        Button { entrySheet = .edit(activity) } label: { ActivityRow(activity: activity) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) { pendingDeletion = activity }
                                    .disabled(!store.canEditSelectedChild)
                            }
                    }
                }
                .navigationTitle("History")
                .disabled(store.loadFailed)
            }
            .tabItem { Label("History", systemImage: "clock") }

            NavigationStack { FamilyView() }
            .tabItem { Label("Family", systemImage: "person.2") }
        }
        .sheet(isPresented: $showingProfile) { ChildProfileView() }
        .sheet(item: $entrySheet) { sheet in
            if let childID = store.selectedChildID {
                switch sheet {
                case .feeding: ActivityEditor(childID: childID, initialDetails: .feeding(kind: .bottle, milliliters: nil, side: nil, minutes: nil))
                case .diaper: ActivityEditor(childID: childID, initialDetails: .diaper(.wet))
                case .edit(let activity): ActivityEditor(childID: childID, initialDetails: activity.details, existing: activity)
                }
            }
        }
        .alert("Couldn't save or open records", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("Delete this activity?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Delete activity", role: .destructive) {
                if let activity = pendingDeletion {
                    _ = store.deleteActivity(activity)
                }
                pendingDeletion = nil
            }
        }
    }

    private func dashboard(_ child: Child) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let summary = DailySummary(activities: store.activities, day: context.date, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A little care, all in one place").font(.subheadline).foregroundStyle(.secondary)
                        Text(child.name).font(.largeTitle.bold())
                        Text(context.date, format: .dateTime.weekday(.wide).month().day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        SummaryTile(title: "Feeds", value: "\(summary.feedings)", symbol: "drop.fill")
                        SummaryTile(title: "Diapers", value: "\(summary.diapers)", symbol: "leaf.fill")
                        SummaryTile(title: "Sleep", value: durationText(summary.sleepSeconds), symbol: "moon.fill")
                    }
                    VStack(spacing: 12) {
                        if store.runningSleepCount > 1 {
                            Text("Both caregivers started sleep offline. End sleep will stop all active timers; overlapping time is counted once.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            quickButton("Log feeding", symbol: "drop.fill") { entrySheet = .feeding }
                            quickButton("Log diaper", symbol: "leaf.fill") { entrySheet = .diaper }
                        }
                        Button { store.toggleSleep() } label: {
                            HStack {
                                Image(systemName: store.runningSleep == nil ? "moon.fill" : "stop.circle.fill")
                                Text(store.runningSleep == nil ? "Start sleep" : "End sleep")
                                Spacer()
                                if let sleep = store.runningSleep {
                                    Text(sleep.startedAt, style: .timer).monospacedDigit()
                                }
                            }
                            .padding().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .accessibilityLabel(store.runningSleep == nil ? "Start sleep" : "End sleep")
                        .accessibilityValue(store.runningSleep.map { durationText(context.date.timeIntervalSince($0.startedAt)) } ?? "")
                        .accessibilityIdentifier("sleep-toggle")
                        .disabled(!store.canEditSelectedChild)
                    }
                    Text("Recent activity").font(.title2.bold())
                    if store.activities.isEmpty {
                        Text("Nothing logged yet. Start with a feeding, diaper change or sleep.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.activities.prefix(5))) { activity in
                        Button { entrySheet = .edit(activity) } label: { ActivityRow(activity: activity) }
                            .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding()
            }
        }
    }

    private func quickButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline).frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .disabled(!store.canEditSelectedChild)
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.teal)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityRow: View {
    let activity: Activity
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: activity.symbol)
                .foregroundStyle(activity.details == .sleep ? .indigo : .teal)
                .frame(width: 28, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title).font(.headline)
                Text(activity.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                if !activity.notes.isEmpty { Text(activity.notes).font(.subheadline) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private var detail: String {
        switch activity.details {
        case .feeding(.bottle, let volume, _, _): return "\((volume ?? 0).formatted(.number.precision(.fractionLength(0...1)))) ml"
        case .feeding(.breast, _, let side, let minutes): return "\(side?.rawValue ?? "") · \((minutes ?? 0).formatted(.number.precision(.fractionLength(0...1)))) min"
        case .sleep:
            if let end = activity.endedAt { return durationText(end.timeIntervalSince(activity.startedAt)) }
            return "Timer running"
        case .diaper: return ""
        }
    }
}

func durationText(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
}
