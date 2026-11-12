import XCTest
@testable import BabyBuddyCore

final class TrackerStoreTests: XCTestCase {
    @MainActor
    func testEditingProfileKeepsItsIDAndActivities() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        let store = TrackerStore(repository: repository)
        XCTAssertTrue(store.saveChild(name: "Robin", birthDate: Date().addingTimeInterval(-86400)))
        let child = try XCTUnwrap(store.selectedChild)
        let activity = Activity(childID: child.id, startedAt: Date(), details: .diaper(.wet))
        XCTAssertTrue(store.saveActivity(activity))
        XCTAssertTrue(store.saveChild(name: "Robin Updated", birthDate: child.birthDate, expected: child))
        XCTAssertEqual(store.snapshot.children.count, 1)
        XCTAssertEqual(store.selectedChild?.id, child.id)
        XCTAssertEqual(store.activities.count, 1)
        XCTAssertEqual(store.activities.first?.childID, child.id)
    }

    @MainActor
    func testStaleOpenEditorCannotOverwriteAnIncomingEdit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        let store = TrackerStore(repository: repository)
        XCTAssertTrue(store.saveChild(name: "Robin", birthDate: Date().addingTimeInterval(-86400)))
        let child = try XCTUnwrap(store.selectedChild)
        XCTAssertTrue(store.saveActivity(Activity(childID: child.id, startedAt: Date(), details: .diaper(.wet))))
        let opened = try XCTUnwrap(store.activities.first)
        let other = try CloudRepository(directory: directory)
        var incoming = try other.load()
        incoming.activities[0].notes = "Updated by partner"
        try other.save(incoming)
        store.reload()
        var edited = opened
        edited.notes = "Stale form text"
        XCTAssertFalse(store.saveActivity(edited, expected: opened))
        XCTAssertEqual(store.activities.first?.notes, "Updated by partner")
        XCTAssertFalse(store.deleteActivity(opened))
        XCTAssertEqual(try repository.load().activities.count, 1)
    }

    @MainActor
    func testAccountChangeImmediatelyHidesRecordsAndBlocksFurtherMutations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        let store = TrackerStore(repository: repository)
        XCTAssertTrue(store.saveChild(name: "Robin", birthDate: Date().addingTimeInterval(-86400)))
        let saved = try repository.load()
        store.handleAccountChange()
        XCTAssertTrue(store.accountChanged)
        XCTAssertTrue(store.loadFailed)
        XCTAssertNil(store.selectedChild)
        XCTAssertEqual(store.snapshot, Snapshot())
        store.reload()
        XCTAssertEqual(store.snapshot, Snapshot())
        XCTAssertFalse(store.saveChild(name: "Other account", birthDate: Date().addingTimeInterval(-86400)))
        XCTAssertEqual(try repository.load(), saved)
    }

    @MainActor
    func testEndSleepStopsAllConcurrentCaregiverTimersAndPersistsThem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        _ = try repository.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        let first = Activity(childID: child.id, startedAt: Date().addingTimeInterval(-120), details: .sleep)
        let second = Activity(childID: child.id, startedAt: Date().addingTimeInterval(-60), details: .sleep)
        try repository.save(Snapshot(children: [child], activities: [first, second]))
        let store = TrackerStore(repository: repository)
        XCTAssertEqual(store.runningSleepCount, 2)
        store.toggleSleep()
        XCTAssertEqual(store.runningSleepCount, 0)
        let restarted = TrackerStore(repository: try CloudRepository(directory: directory))
        XCTAssertEqual(restarted.activities.count, 2)
        XCTAssertEqual(restarted.runningSleepCount, 0)
        XCTAssertTrue(restarted.activities.allSatisfy { $0.endedAt != nil })
    }
}
