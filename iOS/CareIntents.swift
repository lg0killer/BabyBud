import AppIntents
import Foundation

extension FeedingKind: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Feeding type")
    static var caseDisplayRepresentations: [FeedingKind: DisplayRepresentation] = [
        .bottle: "Bottle", .breast: "Breast"
    ]
}

extension DiaperKind: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Diaper type")
    static var caseDisplayRepresentations: [DiaperKind: DisplayRepresentation] = [
        .wet: "Wet", .dirty: "Dirty", .mixed: "Mixed"
    ]
}

extension BreastSide: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Breast side")
    static var caseDisplayRepresentations: [BreastSide: DisplayRepresentation] = [
        .left: "Left", .right: "Right", .both: "Both"
    ]
}

@MainActor
private func intentChild(in store: TrackerStore) throws -> Child {
    store.reload()
    guard !store.loadFailed, let child = store.selectedChild else {
        throw TrackerError.invalid("Open Baby Buddy and create or select your child's profile first.")
    }
    return child
}

struct LogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Baby Feeding"
    static var description = IntentDescription("Log a feeding for the child selected in Baby Buddy, without opening the app.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Feeding type", default: .bottle) var type: FeedingKind
    @Parameter(title: "Amount in milliliters") var milliliters: Double?
    @Parameter(title: "Nursing minutes") var minutes: Double?
    @Parameter(title: "Breast side", default: .both) var side: BreastSide

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TrackerStore.shared
        let child = try intentChild(in: store)
        var amount = milliliters
        var duration = minutes
        if type == .bottle && amount == nil { amount = try await $milliliters.requestValue("How many milliliters?") }
        if type == .breast && duration == nil { duration = try await $minutes.requestValue("How many minutes?") }
        let activity = Activity(childID: child.id, startedAt: Date(), details: .feeding(kind: type,
            milliliters: amount, side: type == .breast ? side : nil, minutes: duration))
        try activity.validate()
        guard store.saveActivity(activity) else { throw TrackerError.invalid(store.errorMessage ?? "Couldn't save the feeding.") }
        return .result(dialog: "Logged a \(type.rawValue.lowercased()) feeding for \(child.name).")
    }
}

struct LogDiaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Baby Diaper"
    static var description = IntentDescription("Log a diaper change for the child selected in Baby Buddy.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Diaper type", default: .wet) var type: DiaperKind

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TrackerStore.shared
        let child = try intentChild(in: store)
        guard store.saveActivity(Activity(childID: child.id, startedAt: Date(), details: .diaper(type))) else {
            throw TrackerError.invalid(store.errorMessage ?? "Couldn't save the diaper change.")
        }
        return .result(dialog: "Logged a \(type.rawValue.lowercased()) diaper for \(child.name).")
    }
}

struct GetLastSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Last Baby Sleep"
    static var description = IntentDescription("Check the most recent sleep for the child selected in Baby Buddy.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TrackerStore.shared
        let child = try intentChild(in: store)
        guard let sleep = store.activities.first(where: { $0.details == .sleep }) else {
            return .result(dialog: "No sleep recorded for \(child.name) yet.")
        }
        let relative = RelativeDateTimeFormatter().localizedString(for: sleep.startedAt, relativeTo: Date())
        if sleep.isRunningSleep { return .result(dialog: "\(child.name) is sleeping. Sleep started \(relative).") }
        return .result(dialog: "\(child.name)'s last sleep started \(relative).")
    }
}

struct CareShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFeedingIntent(), phrases: ["Log a feeding in \(.applicationName)"],
                    shortTitle: "Log feeding", systemImageName: "drop.fill")
        AppShortcut(intent: LogDiaperIntent(), phrases: ["Log a diaper in \(.applicationName)"],
                    shortTitle: "Log diaper", systemImageName: "leaf.fill")
        AppShortcut(intent: GetLastSleepIntent(), phrases: ["Check last sleep in \(.applicationName)"],
                    shortTitle: "Last sleep", systemImageName: "moon.fill")
    }
}
