import Foundation
import Combine

@MainActor
final class TrackerStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published var selectedChildID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var loadFailed = false
    private let repository: any SnapshotRepository

    init(repository: (any SnapshotRepository)? = nil) {
        self.repository = repository ?? JSONSnapshotRepository(url:
            URL.applicationSupportDirectory.appending(path: "BabyBuddy/records.json"))
        reload()
    }

    var selectedChild: Child? { snapshot.children.first { $0.id == selectedChildID } }
    var activities: [Activity] {
        snapshot.activities.filter { $0.childID == selectedChildID }.sorted { $0.startedAt > $1.startedAt }
    }
    var runningSleep: Activity? { activities.first(where: \.isRunningSleep) }

    func reload() {
        do {
            snapshot = try repository.load()
            selectedChildID = snapshot.children.first?.id
            loadFailed = false
        } catch {
            loadFailed = true
            errorMessage = "Saved records could not be opened. Your file has been kept intact. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func commit(_ change: (inout Snapshot) -> Void) -> Bool {
        guard !loadFailed else { return false }
        var next = snapshot
        change(&next)
        do {
            try next.validate()
            try repository.save(next)
            snapshot = next
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveChild(name: String, birthDate: Date) -> Bool {
        var child = selectedChild ?? Child(name: name, birthDate: birthDate)
        child.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        child.birthDate = birthDate
        let saved = commit { data in
            if let index = data.children.firstIndex(where: { $0.id == child.id }) { data.children[index] = child }
            else { data.children.append(child) }
        }
        if saved { selectedChildID = child.id }
        return saved
    }

    func saveActivity(_ activity: Activity) -> Bool {
        var activity = activity
        activity.updatedAt = Date()
        return commit { data in
            if let index = data.activities.firstIndex(where: { $0.id == activity.id }) { data.activities[index] = activity }
            else { data.activities.append(activity) }
        }
    }

    func toggleSleep() {
        if var sleep = runningSleep {
            sleep.endedAt = Date()
            _ = saveActivity(sleep)
        } else if let childID = selectedChildID {
            _ = saveActivity(Activity(childID: childID, startedAt: Date(), details: .sleep))
        }
    }
}
