import Foundation

protocol SnapshotRepository {
    func load() throws -> Snapshot
    func save(_ snapshot: Snapshot) throws
}

struct JSONSnapshotRepository: SnapshotRepository {
    let url: URL

    func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        try snapshot.validate()
        return snapshot
    }

    func save(_ snapshot: Snapshot) throws {
        try snapshot.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        #if os(iOS)
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        #endif
    }
}
