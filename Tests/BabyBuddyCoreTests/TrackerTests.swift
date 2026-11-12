import XCTest
@testable import BabyBuddyCore

final class TrackerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRoundTripKeepsRecordIDsAndRunningSleep() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = JSONSnapshotRepository(url: folder.appendingPathComponent("records.json"))
        let child = Child(name: "Robin", birthDate: now.addingTimeInterval(-86_400))
        let activity = Activity(childID: child.id, startedAt: now, details: .sleep)
        let original = Snapshot(children: [child], activities: [activity])
        try repository.save(original)
        let loaded = try repository.load()
        XCTAssertEqual(loaded, original)
        XCTAssertTrue(try XCTUnwrap(loaded.activities.first).isRunningSleep)
    }

    func testMissingFileIsAnEmptyFirstLaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("records.json")
        XCTAssertEqual(try JSONSnapshotRepository(url: url).load(), Snapshot())
    }

    func testCorruptFileIsNotSilentlyReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let corrupt = Data("not valid JSON".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try JSONSnapshotRepository(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testInvalidSavePreservesExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = JSONSnapshotRepository(url: folder.appendingPathComponent("records.json"))
        try repository.save(Snapshot())
        let originalBytes = try Data(contentsOf: repository.url)
        let orphan = Activity(childID: UUID(), startedAt: now, details: .diaper(.wet))
        XCTAssertThrowsError(try repository.save(Snapshot(activities: [orphan])))
        XCTAssertEqual(try Data(contentsOf: repository.url), originalBytes)
    }

    func testRejectsDuplicateRunningTimersAndIDs() {
        let child = Child(name: "Robin", birthDate: now)
        let a = Activity(childID: child.id, startedAt: now, details: .sleep)
        let b = Activity(childID: child.id, startedAt: now, details: .sleep)
        XCTAssertThrowsError(try Snapshot(children: [child], activities: [a, b]).validate(now: now))
        XCTAssertThrowsError(try Snapshot(children: [child], activities: [a, a]).validate(now: now))
    }

    func testRejectsInvalidBottleAndTimeRange() {
        let id = UUID()
        let bottle = Activity(childID: id, startedAt: now, details: .feeding(kind: .bottle, milliliters: 0, side: nil, minutes: nil))
        XCTAssertThrowsError(try bottle.validate(now: now))
        let sleep = Activity(childID: id, startedAt: now, endedAt: now.addingTimeInterval(-1), details: .sleep)
        XCTAssertThrowsError(try sleep.validate(now: now))
        let future = Activity(childID: id, startedAt: now.addingTimeInterval(60), details: .diaper(.wet))
        XCTAssertThrowsError(try future.validate(now: now))
    }

    func testSleepIsClippedAtMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: now)
        let sleep = Activity(childID: UUID(), startedAt: midnight.addingTimeInterval(-3600), endedAt: midnight.addingTimeInterval(7200), details: .sleep)
        let summary = DailySummary(activities: [sleep], day: midnight, now: midnight.addingTimeInterval(10_800), calendar: calendar)
        XCTAssertEqual(summary.sleepSeconds, 7200)
    }

    func testRunningSleepIncludesElapsedTimeAndDSTDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let sleep = Activity(childID: UUID(), startedAt: day, details: .sleep)
        let summary = DailySummary(activities: [sleep], day: day, now: nextDay, calendar: calendar)
        XCTAssertEqual(summary.sleepSeconds, 23 * 3600)
    }

    func testOverlappingCaregiverSleepLogsCountTimeOnce() {
        let id = UUID()
        let earlier = Activity(childID: id, startedAt: now.addingTimeInterval(-3600), endedAt: now.addingTimeInterval(-600), details: .sleep)
        let later = Activity(childID: id, startedAt: now.addingTimeInterval(-1800), endedAt: now, details: .sleep)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(DailySummary(activities: [earlier, later], day: now, now: now, calendar: calendar).sleepSeconds, 3600)
    }

    func testMidnightCareBelongsOnlyToTheNewDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: now)
        let childID = UUID()
        let records = [
            Activity(childID: childID, startedAt: midnight, details: .diaper(.wet)),
            Activity(childID: childID, startedAt: midnight, details: .feeding(kind: .bottle, milliliters: 60, side: nil, minutes: nil))
        ]
        let previous = DailySummary(activities: records, day: midnight.addingTimeInterval(-1), now: now, calendar: calendar)
        let current = DailySummary(activities: records, day: midnight, now: now, calendar: calendar)
        XCTAssertEqual(previous.feedings, 0)
        XCTAssertEqual(previous.diapers, 0)
        XCTAssertEqual(current.feedings, 1)
        XCTAssertEqual(current.diapers, 1)
    }
}
