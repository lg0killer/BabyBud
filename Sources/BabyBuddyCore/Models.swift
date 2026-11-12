import Foundation

struct Child: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var birthDate: Date
}

enum FeedingKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottle = "Bottle", breast = "Breast"
    var id: String { rawValue }
}

enum BreastSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case left = "Left", right = "Right", both = "Both"
    var id: String { rawValue }
}

enum DiaperKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case wet = "Wet", dirty = "Dirty", mixed = "Mixed"
    var id: String { rawValue }
}

enum ActivityDetails: Codable, Equatable {
    case feeding(kind: FeedingKind, milliliters: Double?, side: BreastSide?, minutes: Double?)
    case diaper(DiaperKind)
    case sleep
}

struct Activity: Identifiable, Codable, Equatable {
    var id = UUID()
    var childID: UUID
    var startedAt: Date
    var endedAt: Date?
    var details: ActivityDetails
    var notes = ""
    var createdAt = Date()
    var updatedAt = Date()

    var isRunningSleep: Bool { details == .sleep && endedAt == nil }
    var title: String {
        switch details {
        case .feeding(let kind, _, _, _): return "\(kind.rawValue) feeding"
        case .diaper(let kind): return "\(kind.rawValue) diaper"
        case .sleep: return isRunningSleep ? "Sleeping" : "Sleep"
        }
    }
    var symbol: String {
        switch details {
        case .feeding: return "drop.fill"
        case .diaper: return "leaf.fill"
        case .sleep: return "moon.fill"
        }
    }

    func validate(now: Date = Date()) throws {
        guard startedAt <= now else { throw TrackerError.invalid("Start time cannot be in the future.") }
        if let endedAt {
            guard endedAt >= startedAt, endedAt <= now else {
                throw TrackerError.invalid("End time must be between the start time and now.")
            }
        }
        switch details {
        case .feeding(let kind, let volume, let side, let minutes):
            if kind == .bottle {
                guard let volume, volume.isFinite, volume > 0 else {
                    throw TrackerError.invalid("Enter a bottle amount greater than zero.")
                }
            } else {
                guard side != nil, let minutes, minutes.isFinite, minutes > 0 else {
                    throw TrackerError.invalid("Choose a side and enter a duration greater than zero.")
                }
            }
        case .diaper, .sleep: break
        }
    }
}

enum TrackerError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct Snapshot: Codable, Equatable {
    var version = 1
    var children: [Child] = []
    var activities: [Activity] = []

    func validate(now: Date = Date(), allowConcurrentSleepTimers: Bool = false) throws {
        guard version == 1 else { throw TrackerError.invalid("This data file requires a newer app version.") }
        guard Set(children.map(\.id)).count == children.count,
              Set(activities.map(\.id)).count == activities.count else {
            throw TrackerError.invalid("Duplicate record identifiers in saved data.")
        }
        for child in children {
            guard !child.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  child.birthDate <= now else { throw TrackerError.invalid("Check the child's name and birth date.") }
        }
        for activity in activities {
            guard children.contains(where: { $0.id == activity.childID }) else {
                throw TrackerError.invalid("An activity refers to a missing child.")
            }
            try activity.validate(now: now)
        }
        for child in children where !allowConcurrentSleepTimers {
            guard activities.filter({ $0.childID == child.id && $0.isRunningSleep }).count <= 1 else {
                throw TrackerError.invalid("A child can only have one running sleep timer.")
            }
        }
    }
}

struct DailySummary {
    var feedings = 0
    var diapers = 0
    var sleepSeconds: TimeInterval = 0

    init(activities: [Activity], day: Date, now: Date = Date(), calendar: Calendar = .current) {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return }
        var sleepIntervals: [DateInterval] = []
        for activity in activities {
            switch activity.details {
            case .feeding:
                if activity.startedAt >= interval.start && activity.startedAt < interval.end { feedings += 1 }
            case .diaper:
                if activity.startedAt >= interval.start && activity.startedAt < interval.end { diapers += 1 }
            case .sleep:
                let start = max(activity.startedAt, interval.start)
                let end = min(activity.endedAt ?? now, interval.end, now)
                if end > start { sleepIntervals.append(DateInterval(start: start, end: end)) }
            }
        }
        // Overlapping caregiver logs must not count the same minute twice.
        var merged: DateInterval?
        for interval in sleepIntervals.sorted(by: { $0.start < $1.start }) {
            if let current = merged, interval.start <= current.end {
                merged = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                sleepSeconds += merged?.duration ?? 0
                merged = interval
            }
        }
        sleepSeconds += merged?.duration ?? 0
    }
}
