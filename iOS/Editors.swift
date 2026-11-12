import SwiftUI

struct ChildProfileView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthDate = Date()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Your child") {
                    TextField("Name", text: $name).textContentType(.givenName)
                    DatePicker("Birth date", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    Text("This profile and its activity records are stored on this iPhone.")
                        .foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(store.selectedChild == nil ? "Welcome" : "Child profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.saveChild(name: name, birthDate: birthDate) { dismiss() }
                        else { error = store.errorMessage; store.errorMessage = nil }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let child = store.selectedChild { name = child.name; birthDate = child.birthDate }
            }
        }
    }
}

struct ActivityEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let childID: UUID
    let initialDetails: ActivityDetails
    var existing: Activity?
    @State private var startedAt = Date()
    @State private var endedAt = Date()
    @State private var running = false
    @State private var feedingKind = FeedingKind.bottle
    @State private var side = BreastSide.both
    @State private var amount = ""
    @State private var minutes = ""
    @State private var diaperKind = DiaperKind.wet
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Started", selection: $startedAt, in: ...Date())
                    if initialDetails == .sleep {
                        if running {
                            Label("Sleep timer is running", systemImage: "moon.fill")
                            Button("End sleep now") { endedAt = Date(); running = false }
                        } else { DatePicker("Ended", selection: $endedAt, in: ...Date()) }
                    }
                }
                switch initialDetails {
                case .feeding:
                    Section("Feeding") {
                        Picker("Type", selection: $feedingKind) {
                            ForEach(FeedingKind.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if feedingKind == .bottle {
                            TextField("Amount (ml)", text: $amount).keyboardType(.decimalPad)
                        } else {
                            Picker("Side", selection: $side) {
                                ForEach(BreastSide.allCases) { Text($0.rawValue).tag($0) }
                            }
                            TextField("Duration (minutes)", text: $minutes).keyboardType(.decimalPad)
                        }
                    }
                case .diaper:
                    Section("Diaper") {
                        Picker("Type", selection: $diaperKind) {
                            ForEach(DiaperKind.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                case .sleep: EmptyView()
                }
                Section("Notes") { TextField("Anything to remember?", text: $notes, axis: .vertical).lineLimit(3...6) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(existing?.title ?? "Log activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        if let existing {
            startedAt = existing.startedAt
            endedAt = existing.endedAt ?? Date()
            running = existing.isRunningSleep
            notes = existing.notes
        }
        switch initialDetails {
        case .feeding(let kind, let volume, let savedSide, let duration):
            feedingKind = kind
            amount = volume.map { String($0) } ?? ""
            side = savedSide ?? .both
            minutes = duration.map { String($0) } ?? ""
        case .diaper(let kind): diaperKind = kind
        case .sleep: break
        }
    }

    private func number(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        return Double(normalized)
    }

    private func save() {
        var activity = existing ?? Activity(childID: childID, startedAt: startedAt, details: initialDetails)
        activity.startedAt = startedAt
        activity.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch initialDetails {
        case .feeding:
            activity.details = .feeding(kind: feedingKind,
                milliliters: feedingKind == .bottle ? number(amount) : nil,
                side: feedingKind == .breast ? side : nil,
                minutes: feedingKind == .breast ? number(minutes) : nil)
        case .diaper: activity.details = .diaper(diaperKind)
        case .sleep: activity.endedAt = running ? nil : endedAt
        }
        do {
            try activity.validate()
            if store.saveActivity(activity) { dismiss() }
            else { error = store.errorMessage; store.errorMessage = nil }
        } catch { self.error = error.localizedDescription }
    }
}
