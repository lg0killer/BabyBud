import Foundation
import CoreData
import CloudKit

/// A separate object per activity lets CloudKit merge additions from two caregivers.
/// Sharing the child shares its related activity graph, rather than a whole JSON file.
final class CloudRepository: SnapshotRepository {
    enum Mutation { case update, delete }
    let container: NSPersistentCloudKitContainer
    let cloudIdentifier: String?
    private(set) var privateStore: NSPersistentStore!
    private(set) var sharedStore: NSPersistentStore?
    private var baseline = Snapshot()
    private let authorizationCheck: ((NSManagedObjectID, Mutation) -> Bool)?

    init(directory: URL, cloudIdentifier: String? = nil, legacyURL: URL? = nil,
         authorizationCheck: ((NSManagedObjectID, Mutation) -> Bool)? = nil) throws {
        self.cloudIdentifier = cloudIdentifier
        self.authorizationCheck = authorizationCheck
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = NSPersistentCloudKitContainer(name: "BabyBuddy", managedObjectModel: Self.model())
        let own = Self.description(url: directory.appendingPathComponent("private.sqlite"),
                                   cloudIdentifier: cloudIdentifier, scope: .private)
        var descriptions = [own]
        if cloudIdentifier != nil {
            descriptions.append(Self.description(url: directory.appendingPathComponent("shared.sqlite"),
                                                  cloudIdentifier: cloudIdentifier, scope: .shared))
        }
        container.persistentStoreDescriptions = descriptions
        var failure: Error?
        container.loadPersistentStores { _, error in if let error { failure = error } }
        if let failure { throw failure }
        privateStore = container.persistentStoreCoordinator.persistentStores.first { $0.url == own.url }
        sharedStore = container.persistentStoreCoordinator.persistentStores.first { $0.url != own.url }
        guard privateStore != nil else { throw TrackerError.invalid("The local database could not be opened.") }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy

        // The legacy file is deliberately retained. A marker prevents reimport after deleting records.
        var metadata = container.persistentStoreCoordinator.metadata(for: privateStore)
        if metadata["BabyBuddyLegacyImport"] == nil {
            let current = try load()
            if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
                let legacy = try JSONSnapshotRepository(url: legacyURL).load()
                guard current.children.isEmpty && current.activities.isEmpty else {
                    throw TrackerError.invalid("Both a legacy file and database contain records. Import was stopped to preserve them.")
                }
                try save(legacy)
            }
            metadata = container.persistentStoreCoordinator.metadata(for: privateStore)
            metadata["BabyBuddyLegacyImport"] = true
            container.persistentStoreCoordinator.setMetadata(metadata, for: privateStore)
        }
    }

    private static func description(url: URL, cloudIdentifier: String?, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let result = NSPersistentStoreDescription(url: url)
        result.shouldAddStoreAsynchronously = false
        result.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        result.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        #if os(iOS)
        result.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                         forKey: NSPersistentStoreFileProtectionKey)
        #endif
        if let cloudIdentifier {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudIdentifier)
            options.databaseScope = scope
            result.cloudKitContainerOptions = options
        }
        return result
    }

    static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let child = NSEntityDescription()
        child.name = "BabyProfile"
        child.managedObjectClassName = "NSManagedObject"
        let log = NSEntityDescription()
        log.name = "BabyActivity"
        log.managedObjectClassName = "NSManagedObject"
        func attributes() -> [NSAttributeDescription] {
            [("uuid", NSAttributeType.UUIDAttributeType), ("payload", .binaryDataAttributeType)].map { name, type in
                let attribute = NSAttributeDescription()
                attribute.name = name
                attribute.attributeType = type
                attribute.isOptional = true
                return attribute
            }
        }
        let activities = NSRelationshipDescription()
        activities.name = "activities"
        activities.destinationEntity = log
        activities.minCount = 0
        activities.maxCount = 0
        activities.isOptional = true
        activities.deleteRule = .cascadeDeleteRule
        let parent = NSRelationshipDescription()
        parent.name = "child"
        parent.destinationEntity = child
        parent.minCount = 0
        parent.maxCount = 1
        parent.isOptional = true
        parent.deleteRule = .nullifyDeleteRule
        activities.inverseRelationship = parent
        parent.inverseRelationship = activities
        child.properties = attributes() + [activities]
        log.properties = attributes() + [parent]
        model.entities = [child, log]
        return model
    }

    private func rows(_ entity: String, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
    }

    private func decode<T: Decodable>(_ type: T.Type, row: NSManagedObject) throws -> T {
        guard let data = row.value(forKey: "payload") as? Data else {
            throw TrackerError.invalid("A database record is incomplete. Wait for iCloud to finish syncing and try again.")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func permits(_ id: NSManagedObjectID, mutation: Mutation) -> Bool {
        if let authorizationCheck { return authorizationCheck(id, mutation) }
        guard cloudIdentifier != nil else { return true }
        switch mutation {
        case .update: return container.canUpdateRecord(forManagedObjectWith: id)
        case .delete: return container.canDeleteRecord(forManagedObjectWith: id)
        }
    }

    private func requirePermission(_ row: NSManagedObject, mutation: Mutation) throws {
        guard permits(row.objectID, mutation: mutation) else {
            throw TrackerError.invalid("You no longer have permission to change this family's records. Refresh Family to check your access.")
        }
    }

    func canEditChild(_ id: UUID) -> Bool {
        guard let objectID = try? objectID(for: id) else { return false }
        return permits(objectID, mutation: .update)
    }

    func load() throws -> Snapshot {
        let context = container.newBackgroundContext()
        let snapshot: Snapshot = try context.performAndWait {
            let children = try rows("BabyProfile", in: context).map { row in
                let child = try decode(Child.self, row: row)
                guard row.value(forKey: "uuid") as? UUID == child.id else {
                    throw TrackerError.invalid("A child record has inconsistent identifiers. No records were changed.")
                }
                return child
            }
            let activities = try rows("BabyActivity", in: context).map { row in
                let activity = try decode(Activity.self, row: row)
                guard row.value(forKey: "uuid") as? UUID == activity.id,
                      let parent = row.value(forKey: "child") as? NSManagedObject,
                      parent.value(forKey: "uuid") as? UUID == activity.childID else {
                    throw TrackerError.invalid("An activity does not match its child's record. Wait for iCloud to finish and refresh.")
                }
                return activity
            }
            let result = Snapshot(children: children.sorted { $0.name < $1.name }, activities: activities)
            // Two caregivers may start timers offline. Keep both visible so either
            // caregiver can end them, rather than making the database unreadable.
            try result.validate(allowConcurrentSleepTimers: true)
            return result
        }
        baseline = snapshot
        return snapshot
    }

    func save(_ snapshot: Snapshot) throws {
        try snapshot.validate(allowConcurrentSleepTimers: true)
        let previous = baseline
        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        try context.performAndWait {
            let childRows = try rows("BabyProfile", in: context)
            let activityRows = try rows("BabyActivity", in: context)
            func indexed(_ rows: [NSManagedObject]) throws -> [UUID: NSManagedObject] {
                var result: [UUID: NSManagedObject] = [:]
                for row in rows {
                    guard let id = row.value(forKey: "uuid") as? UUID, result[id] == nil else {
                        throw TrackerError.invalid("Duplicate or incomplete database records. No changes were saved.")
                    }
                    result[id] = row
                }
                return result
            }
            var children = try indexed(childRows)
            let activities = try indexed(activityRows)
            let encoder = JSONEncoder()
            func check<T: Codable & Equatable>(_ old: T?, _ row: NSManagedObject?) throws {
                if let old {
                    guard let row, try decode(T.self, row: row) == old else {
                        throw TrackerError.invalid("This record changed on another device. Refresh and try your change again.")
                    }
                } else if row != nil {
                    throw TrackerError.invalid("This record already exists. Refresh before trying again.")
                }
            }
            for child in snapshot.children {
                let old = previous.children.first { $0.id == child.id }
                guard old != child else { continue }
                try check(old, children[child.id])
                if let row = children[child.id] { try requirePermission(row, mutation: .update) }
                let row = children[child.id] ?? NSEntityDescription.insertNewObject(forEntityName: "BabyProfile", into: context)
                if row.isInserted { context.assign(row, to: privateStore) }
                row.setValue(child.id, forKey: "uuid")
                row.setValue(try encoder.encode(child), forKey: "payload")
                children[child.id] = row
            }
            for activity in snapshot.activities {
                let old = previous.activities.first { $0.id == activity.id }
                guard old != activity else { continue }
                try check(old, activities[activity.id])
                if let old, old.childID != activity.childID {
                    throw TrackerError.invalid("Activities cannot be moved between child profiles.")
                }
                guard let child = children[activity.childID], !child.isDeleted else {
                    throw TrackerError.invalid("This child's profile is no longer available. Refresh your records.")
                }
                if let row = activities[activity.id] { try requirePermission(row, mutation: .update) }
                // Appending to a share also requires current write permission on its root.
                if !child.isInserted { try requirePermission(child, mutation: .update) }
                let row = activities[activity.id] ?? NSEntityDescription.insertNewObject(forEntityName: "BabyActivity", into: context)
                if row.isInserted, let store = child.objectID.persistentStore { context.assign(row, to: store) }
                row.setValue(activity.id, forKey: "uuid")
                row.setValue(try encoder.encode(activity), forKey: "payload")
                row.setValue(child, forKey: "child")
            }
            for old in previous.activities where !snapshot.activities.contains(where: { $0.id == old.id }) {
                if let row = activities[old.id] {
                    try check(old, row)
                    try requirePermission(row, mutation: .delete)
                    context.delete(row)
                }
            }
            for old in previous.children where !snapshot.children.contains(where: { $0.id == old.id }) {
                if let row = children[old.id] {
                    try check(old, row)
                    try requirePermission(row, mutation: .delete)
                    context.delete(row)
                }
            }
            if context.hasChanges { try context.save() }
        }
        baseline = snapshot
    }

    func objectID(for childID: UUID) throws -> NSManagedObjectID {
        let context = container.viewContext
        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "BabyProfile")
            request.predicate = NSPredicate(format: "uuid == %@", childID as NSUUID)
            guard let child = try context.fetch(request).first else {
                throw TrackerError.invalid("Create or select a child before sharing.")
            }
            return child.objectID
        }
    }
}
