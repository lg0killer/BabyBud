import Foundation
import Combine
import CoreData
import CloudKit

// Shared by SwiftUI and App Intents; kept in the package so care mutations can be tested directly.
@MainActor
final class TrackerStore: ObservableObject {
    static let shared = TrackerStore()
    @Published private(set) var snapshot = Snapshot()
    @Published var selectedChildID: UUID? {
        didSet {
            if persistsSelection {
                UserDefaults.standard.set(selectedChildID?.uuidString, forKey: "SelectedChildID")
            }
        }
    }
    @Published var errorMessage: String?
    @Published private(set) var loadFailed = false
    @Published private(set) var syncStatus = "Waiting for iCloud. Local changes are saved immediately."
    private var repository: (any SnapshotRepository)?
    private var remoteObserver: NSObjectProtocol?
    private var syncObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private let persistsSelection: Bool
    @Published private(set) var accountChanged = false

    var cloudRepository: CloudRepository? { repository as? CloudRepository }
    static var cloudIdentifier: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "BabyBuddyCloudContainer") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    init(repository: (any SnapshotRepository)? = nil) {
        self.repository = repository
        persistsSelection = repository == nil && ProcessInfo.processInfo.environment["BABYBUDDY_UI_TEST_ID"] == nil
        if persistsSelection {
            selectedChildID = UserDefaults.standard.string(forKey: "SelectedChildID").flatMap(UUID.init(uuidString:))
        }
        reload()
        if let database = cloudRepository {
            if database.cloudIdentifier != nil {
                accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged,
                    object: nil, queue: nil) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.handleAccountChange()
                    }
                }
            }
            remoteObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
                object: database.container.persistentStoreCoordinator, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
            syncObserver = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: database.container, queue: nil) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
                Task { @MainActor in
                    if self?.accountChanged == true { return }
                    if let error = event.error { self?.syncStatus = "iCloud needs attention: \(error.localizedDescription)" }
                    else if event.endDate == nil { self?.syncStatus = "Syncing with iCloud…" }
                    else if event.succeeded {
                        self?.syncStatus = "Last iCloud transfer: \(event.endDate?.formatted(date: .omitted, time: .shortened) ?? "just now")."
                        self?.reload()
                    }
                }
            }
        }
    }

    deinit {
        for observer in [remoteObserver, syncObserver, accountObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func handleAccountChange() {
        accountChanged = true
        loadFailed = true
        snapshot = Snapshot()
        selectedChildID = nil
        syncStatus = "Your iCloud account changed. Close and reopen Baby Buddy before using family records."
        errorMessage = syncStatus
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        guard !accountChanged else { errorMessage = syncStatus; return }
        guard let repository = cloudRepository, let sharedStore = repository.sharedStore,
              metadata.containerIdentifier == repository.cloudIdentifier else {
            errorMessage = "This invitation needs a family-sharing build configured for the same iCloud container."
            return
        }
        syncStatus = "Accepting family invitation…"
        repository.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            Task { @MainActor in
                if let error { self.errorMessage = error.localizedDescription }
                else { self.syncStatus = "Invitation accepted. Waiting for family records to download."; self.reload() }
            }
        }
    }

    var selectedChild: Child? { snapshot.children.first { $0.id == selectedChildID } }
    var canEditSelectedChild: Bool {
        guard !loadFailed, let child = selectedChild else { return false }
        return cloudRepository?.canEditChild(child.id) ?? true
    }
    var activities: [Activity] {
        snapshot.activities.filter { $0.childID == selectedChildID }.sorted { $0.startedAt > $1.startedAt }
    }
    var runningSleep: Activity? { activities.first(where: \.isRunningSleep) }
    var runningSleepCount: Int { activities.filter(\.isRunningSleep).count }

    func reload() {
        guard !accountChanged else { return }
        do {
            if repository == nil {
                var directory = URL.applicationSupportDirectory.appending(path: "BabyBuddy")
                var cloudIdentifier = Self.cloudIdentifier
                #if DEBUG
                if let testID = ProcessInfo.processInfo.environment["BABYBUDDY_UI_TEST_ID"], UUID(uuidString: testID) != nil {
                    directory = URL.applicationSupportDirectory.appending(path: "BabyBuddyUITests/\(testID)")
                    cloudIdentifier = nil
                }
                #endif
                repository = try CloudRepository(directory: directory,
                    cloudIdentifier: cloudIdentifier,
                    legacyURL: directory.appending(path: "records.json"))
            }
            guard let repository else { return }
            snapshot = try repository.load()
            if !snapshot.children.contains(where: { $0.id == selectedChildID }) {
                selectedChildID = snapshot.children.first?.id
            }
            loadFailed = false
        } catch {
            loadFailed = true
            snapshot = Snapshot()
            selectedChildID = nil
            errorMessage = "Saved records could not be opened. Your file has been kept intact. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func commit(_ change: (inout Snapshot) -> Void) -> Bool {
        guard !loadFailed, let repository else { return false }
        var next = snapshot
        change(&next)
        do {
            try next.validate(allowConcurrentSleepTimers: true)
            try repository.save(next)
            // Include remote additions that arrived while this form was being edited.
            snapshot = try repository.load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveChild(name: String, birthDate: Date, expected: Child? = nil) -> Bool {
        if let expected, snapshot.children.first(where: { $0.id == expected.id }) != expected {
            errorMessage = "This profile changed while you were editing it. Reopen the profile and try again."
            return false
        }
        var child = expected ?? Child(name: name, birthDate: birthDate)
        child.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        child.birthDate = birthDate
        let saved = commit { data in
            if let index = data.children.firstIndex(where: { $0.id == child.id }) { data.children[index] = child }
            else { data.children.append(child) }
        }
        if saved { selectedChildID = child.id }
        return saved
    }

    func saveActivity(_ activity: Activity, expected: Activity? = nil) -> Bool {
        if let expected, snapshot.activities.first(where: { $0.id == expected.id }) != expected {
            errorMessage = "This activity changed while you were editing it. Reopen it and try again."
            return false
        }
        var activity = activity
        activity.updatedAt = Date()
        return commit { data in
            if let index = data.activities.firstIndex(where: { $0.id == activity.id }) { data.activities[index] = activity }
            else { data.activities.append(activity) }
        }
    }

    func deleteActivity(_ expected: Activity) -> Bool {
        guard snapshot.activities.first(where: { $0.id == expected.id }) == expected else {
            errorMessage = "This activity changed. Review it before deleting."
            return false
        }
        return commit { $0.activities.removeAll { $0.id == expected.id } }
    }

    func toggleSleep() {
        if runningSleep != nil {
            let end = Date()
            _ = commit { data in
                for index in data.activities.indices where data.activities[index].childID == selectedChildID && data.activities[index].isRunningSleep {
                    data.activities[index].endedAt = end
                    data.activities[index].updatedAt = end
                }
            }
        } else if let childID = selectedChildID {
            _ = saveActivity(Activity(childID: childID, startedAt: Date(), details: .sleep))
        }
    }
}
