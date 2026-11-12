import XCTest
import CoreData
@testable import BabyBuddyCore

final class CloudRepositoryTests: XCTestCase {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testSQLiteRoundTripAndTimerRestoration() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        _ = try repository.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        let timer = Activity(childID: child.id, startedAt: Date().addingTimeInterval(-60), details: .sleep)
        try repository.save(Snapshot(children: [child], activities: [timer]))
        let reopened = try CloudRepository(directory: directory)
        let loaded = try reopened.load()
        XCTAssertEqual(loaded.children, [child])
        XCTAssertEqual(loaded.activities, [timer])
    }

    func testImportRetainsLegacyFileAndDoesNotReimportDeletedRecords() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("records.json")
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        let snapshot = Snapshot(children: [child])
        try JSONSnapshotRepository(url: legacyURL).save(snapshot)
        let bytes = try Data(contentsOf: legacyURL)
        let repository = try CloudRepository(directory: directory, legacyURL: legacyURL)
        XCTAssertEqual(try repository.load(), snapshot)
        XCTAssertEqual(try Data(contentsOf: legacyURL), bytes)
        try repository.save(Snapshot())
        let reopened = try CloudRepository(directory: directory, legacyURL: legacyURL)
        XCTAssertEqual(try reopened.load(), Snapshot())
    }

    func testCorruptLegacyFileIsNotOverwritten() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent("records.json")
        let bytes = Data("broken".utf8)
        try bytes.write(to: legacyURL)
        XCTAssertThrowsError(try CloudRepository(directory: directory, legacyURL: legacyURL))
        XCTAssertEqual(try Data(contentsOf: legacyURL), bytes)
    }

    func testStaleSavePreservesOtherCaregiversAdditions() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try CloudRepository(directory: directory)
        _ = try first.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        try first.save(Snapshot(children: [child]))
        let second = try CloudRepository(directory: directory)
        var a = try first.load()
        var b = try second.load()
        let diaper = Activity(childID: child.id, startedAt: Date(), details: .diaper(.wet))
        let feed = Activity(childID: child.id, startedAt: Date(), details: .feeding(kind: .bottle, milliliters: 90, side: nil, minutes: nil))
        a.activities.append(diaper)
        b.activities.append(feed)
        try first.save(a)
        try second.save(b)
        XCTAssertEqual(Set(try first.load().activities.map(\.id)), [diaper.id, feed.id])
    }

    func testStaleEditDoesNotOverwriteNewerEdit() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try CloudRepository(directory: directory)
        _ = try first.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        try first.save(Snapshot(children: [child]))
        let second = try CloudRepository(directory: directory)
        var a = try first.load()
        var b = try second.load()
        a.children[0].name = "First edit"
        b.children[0].name = "Stale edit"
        try first.save(a)
        XCTAssertThrowsError(try second.save(b))
        XCTAssertEqual(try second.load().children.first?.name, "First edit")
    }

    func testConcurrentOfflineTimersRemainReadableAndCanBeStopped() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try CloudRepository(directory: directory)
        _ = try first.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        try first.save(Snapshot(children: [child]))
        let second = try CloudRepository(directory: directory)
        var a = try first.load()
        var b = try second.load()
        a.activities.append(Activity(childID: child.id, startedAt: Date().addingTimeInterval(-120), details: .sleep))
        b.activities.append(Activity(childID: child.id, startedAt: Date().addingTimeInterval(-60), details: .sleep))
        try first.save(a)
        try second.save(b)
        var merged = try first.load()
        XCTAssertEqual(merged.activities.filter(\.isRunningSleep).count, 2)
        for index in merged.activities.indices { merged.activities[index].endedAt = Date() }
        try first.save(merged)
        XCTAssertTrue(try second.load().activities.allSatisfy { !$0.isRunningSleep })
    }

    func testReadOnlyFamilyRejectsNewActivityWithoutChangingHistory() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try CloudRepository(directory: directory)
        _ = try owner.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        try owner.save(Snapshot(children: [child]))
        let reader = try CloudRepository(directory: directory, authorizationCheck: { _, _ in false })
        var proposed = try reader.load()
        XCTAssertFalse(reader.canEditChild(child.id))
        proposed.activities.append(Activity(childID: child.id, startedAt: Date(), details: .diaper(.wet)))
        XCTAssertThrowsError(try reader.save(proposed))
        XCTAssertTrue(try owner.load().activities.isEmpty)
    }

    func testDeniedDeletionRollsBackOtherChangesInTheSameSave() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try CloudRepository(directory: directory)
        _ = try owner.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        let diaper = Activity(childID: child.id, startedAt: Date(), details: .diaper(.wet))
        let original = Snapshot(children: [child], activities: [diaper])
        try owner.save(original)
        let writer = try CloudRepository(directory: directory, authorizationCheck: { _, mutation in
            switch mutation { case .update: return true; case .delete: return false }
        })
        var proposed = try writer.load()
        proposed.children[0].name = "Unsaved edit"
        proposed.activities.removeAll()
        XCTAssertThrowsError(try writer.save(proposed))
        XCTAssertEqual(try owner.load(), original)
    }

    func testActivityCannotMoveBetweenChildShares() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        _ = try repository.load()
        let first = Child(name: "Alex", birthDate: Date().addingTimeInterval(-86400))
        let second = Child(name: "Robin", birthDate: first.birthDate)
        let activity = Activity(childID: first.id, startedAt: Date(), details: .diaper(.wet))
        let original = Snapshot(children: [first, second], activities: [activity])
        try repository.save(original)
        var proposed = try repository.load()
        proposed.activities[0].childID = second.id
        XCTAssertThrowsError(try repository.save(proposed))
        XCTAssertEqual(try repository.load(), original)
    }

    func testRemovedFamilyCannotBeResurrectedByAStaleAddition() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try CloudRepository(directory: directory)
        _ = try owner.load()
        let child = Child(name: "Robin", birthDate: Date().addingTimeInterval(-86400))
        try owner.save(Snapshot(children: [child]))
        let participant = try CloudRepository(directory: directory)
        var stale = try participant.load()
        try owner.save(Snapshot())
        stale.activities.append(Activity(childID: child.id, startedAt: Date(), details: .diaper(.wet)))
        XCTAssertThrowsError(try participant.save(stale))
        XCTAssertEqual(try owner.load(), Snapshot())
    }

    func testMismatchedFamilyRelationshipIsNotDisplayedOrSilentlyRepaired() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CloudRepository(directory: directory)
        _ = try repository.load()
        let first = Child(name: "Alex", birthDate: Date().addingTimeInterval(-86400))
        let second = Child(name: "Robin", birthDate: first.birthDate)
        let activity = Activity(childID: first.id, startedAt: Date(), details: .diaper(.wet))
        try repository.save(Snapshot(children: [first, second], activities: [activity]))
        let context = repository.container.newBackgroundContext()
        let originalPayload: Data = try context.performAndWait {
            let roots = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "BabyProfile"))
            let wrongRoot = try XCTUnwrap(roots.first { $0.value(forKey: "uuid") as? UUID == second.id })
            let row = try XCTUnwrap(context.fetch(NSFetchRequest<NSManagedObject>(entityName: "BabyActivity")).first)
            let payload = try XCTUnwrap(row.value(forKey: "payload") as? Data)
            row.setValue(wrongRoot, forKey: "child")
            try context.save()
            return payload
        }
        XCTAssertThrowsError(try repository.load())
        try context.performAndWait {
            let row = try XCTUnwrap(context.fetch(NSFetchRequest<NSManagedObject>(entityName: "BabyActivity")).first)
            XCTAssertEqual(row.value(forKey: "payload") as? Data, originalPayload)
        }
    }
}
