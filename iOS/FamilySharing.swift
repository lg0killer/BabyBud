import SwiftUI
import CloudKit
import CoreData
import UIKit

struct FamilyShare: Identifiable {
    var id: CKRecord.ID { share.recordID }
    let share: CKShare
    let container: CKContainer
    let persistentStore: NSPersistentStore
}

struct FamilyView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var sharing: FamilyShare?
    @State private var preparing = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Your family") {
                if !store.snapshot.children.isEmpty {
                    Picker("Child", selection: $store.selectedChildID) {
                        ForEach(store.snapshot.children) { child in Text(child.name).tag(Optional(child.id)) }
                    }
                }
                Button {
                    Task { await prepareShare() }
                } label: {
                    HStack {
                        Label("Invite or manage caregivers", systemImage: "person.badge.plus")
                        if preparing { Spacer(); ProgressView() }
                    }
                }
                .disabled(preparing || store.selectedChild == nil || store.loadFailed || TrackerStore.cloudIdentifier == nil)
                Text("Invite your partner using their Apple Account. Both caregivers can log care offline; iCloud sends changes when connected.")
                    .foregroundStyle(.secondary)
                if store.selectedChild != nil && !store.canEditSelectedChild {
                    Label("Read-only access", systemImage: "lock")
                    Text("You can view this child's records. Ask the owner for editing permission to log care.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("iCloud") {
                if TrackerStore.cloudIdentifier == nil {
                    Label("Local testing build", systemImage: "iphone")
                    Text("Family sharing needs a signed build with an iCloud container. Your records stay on this device until that is configured.")
                } else {
                    Label("iCloud configured", systemImage: "icloud")
                    Text(store.syncStatus)
                    Button("Refresh records") { store.reload() }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            Section("Join an invitation") {
                Text("Open your partner's iCloud invitation on this device and accept it. Their child's profile will appear here after iCloud finishes downloading it. You don't need to create a second profile.")
            }
            Section("Storage") {
                Text("Records are saved on this device after each change. No self-hosted server is required.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Family")
        .sheet(item: $sharing) { item in CloudSharingSheet(item: item, store: store) }
    }

    @MainActor
    private func prepareShare() async {
        guard let repository = store.cloudRepository, let identifier = repository.cloudIdentifier,
              let child = store.selectedChild else { return }
        preparing = true
        message = nil
        defer { preparing = false }
        do {
            let cloud = CKContainer(identifier: identifier)
            guard try await cloud.accountStatus() == .available else {
                throw TrackerError.invalid("Sign in to iCloud in Settings to invite caregivers.")
            }
            let objectID = try repository.objectID(for: child.id)
            guard let persistentStore = objectID.persistentStore else {
                throw TrackerError.invalid("The child profile hasn't finished saving. Try again shortly.")
            }
            if let existing = try repository.container.fetchShares(matching: [objectID])[objectID] {
                sharing = FamilyShare(share: existing, container: cloud, persistentStore: persistentStore)
            } else {
                let object = try repository.container.viewContext.existingObject(with: objectID)
                let result: (CKShare, CKContainer) = try await withCheckedThrowingContinuation { continuation in
                    repository.container.share([object], to: nil) { _, share, container, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let share, let container { continuation.resume(returning: (share, container)) }
                        else { continuation.resume(throwing: TrackerError.invalid("iCloud could not create an invitation. Try again.")) }
                    }
                }
                result.0[CKShare.SystemFieldKey.title] = "\(child.name)'s care" as CKRecordValue
                result.0.publicPermission = .none
                let _: CKShare = try await withCheckedThrowingContinuation { continuation in
                    repository.container.persistUpdatedShare(result.0, in: persistentStore) { share, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let share { continuation.resume(returning: share) }
                        else { continuation.resume(throwing: TrackerError.invalid("The invitation could not be saved.")) }
                    }
                }
                sharing = FamilyShare(share: result.0, container: result.1, persistentStore: persistentStore)
            }
        } catch { message = error.localizedDescription }
    }
}

private struct CloudSharingSheet: UIViewControllerRepresentable {
    let item: FamilyShare
    let store: TrackerStore

    func makeCoordinator() -> Coordinator { Coordinator(item: item, store: store) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: item.share, container: item.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let item: FamilyShare
        let store: TrackerStore
        init(item: FamilyShare, store: TrackerStore) { self.item = item; self.store = store }

        func itemTitle(for csc: UICloudSharingController) -> String? { "Baby Buddy family" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            store.errorMessage = error.localizedDescription
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share, let repository = store.cloudRepository else { return }
            repository.container.persistUpdatedShare(share, in: item.persistentStore) { _, error in
                Task { @MainActor in
                    if let error { self.store.errorMessage = error.localizedDescription }
                    else { self.store.reload() }
                }
            }
        }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            guard let repository = store.cloudRepository else { return }
            // A participant leaving must remove that family's local shared graph.
            // The owner's private records must remain intact when they stop sharing.
            if item.persistentStore == repository.sharedStore {
                repository.container.purgeObjectsAndRecordsInZone(with: item.share.recordID.zoneID,
                    in: item.persistentStore) { _, error in
                    Task { @MainActor in
                        if let error { self.store.errorMessage = error.localizedDescription }
                        self.store.reload()
                    }
                }
            } else { store.reload() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if TrackerStore.cloudIdentifier != nil { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        TrackerStore.shared.errorMessage = "iCloud background updates couldn't register. \(error.localizedDescription)"
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = FamilySceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in TrackerStore.shared.acceptShare(cloudKitShareMetadata) }
    }
}

final class FamilySceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            TrackerStore.shared.acceptShare(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        TrackerStore.shared.acceptShare(cloudKitShareMetadata)
    }
}
