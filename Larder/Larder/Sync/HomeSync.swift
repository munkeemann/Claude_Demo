import CloudKit
import Foundation
import InventoryCore
import Observation
import SwiftData
import UIKit

enum HomeSyncError: LocalizedError {
    case iCloudUnavailable(CKAccountStatus)
    case alreadyInHome
    case notSetUp
    case shareUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable(let status):
            status == .restricted
                ? "iCloud is restricted on this iPhone, so sharing isn't available."
                : "Sign in to iCloud in the Settings app to share your inventory."
        case .alreadyInHome:
            "This phone is already in a shared home. Leave it in Settings first."
        case .notSetUp:
            "Sharing hasn't been set up yet."
        case .shareUnavailable:
            "The invitation couldn't be opened. Ask for a new link."
        }
    }
}

/// Shares one inventory between the people in a household through iCloud.
///
/// The owner's inventory lives in a record zone in their private CloudKit
/// database, shared in full with a zone-wide `CKShare`. Everyone else reads
/// and writes it through their shared database. `CKSyncEngine` does the
/// fetching, sending, retries and push handling; this class maps records
/// to SwiftData objects.
///
/// Local changes are found by diffing: every few seconds (and when the app
/// goes to the background) each shared object is encoded and compared with
/// what iCloud last confirmed (`SyncRecordState`). That catches every kind
/// of change, including cascaded deletes, without hooks in the rest of the
/// app. When two phones change the same record, the later change wins.
@Observable
@MainActor
final class HomeSync {
    static let shared = HomeSync()

    static let containerIdentifier = "iCloud.com.munkeemann.larder"
    /// The one record type in the CloudKit schema. Its fields: `kind`
    /// (String) and `payload` (String, a `SyncEnvelope` as JSON).
    static let recordType = "LarderRecord"
    static let zoneName = "LarderHome"

    enum Role: String, Codable {
        case owner
        case participant
    }

    struct Config: Codable {
        var role: Role
        var zoneName: String
        var zoneOwnerName: String
        var homeName: String
        var engineState: CKSyncEngine.State.Serialization?
        /// A joining phone uploads nothing until it has the home's records,
        /// so its built-in locations and products merge instead of
        /// duplicating. Stored so a relaunch mid-join keeps waiting.
        var awaitingFirstFetch: Bool?

        var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName) }
    }

    enum Status: Equatable {
        case off
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    struct Member: Identifiable, Equatable {
        let id: String
        let name: String
        let isOwner: Bool
        let isPending: Bool
    }

    // Observed by the UI.
    private(set) var config: Config?
    private(set) var status: Status = .off
    private(set) var members: [Member] = []
    /// An invitation waiting for the user to accept or decline.
    var pendingInvitation: CKShare.Metadata?
    /// A one-time message, e.g. that the owner stopped sharing.
    var notice: String?

    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var scanTimer: Timer?
    @ObservationIgnored private var fetchTimer: Timer?
    @ObservationIgnored private var isApplyingRemote = false
    /// Records applied before something they reference had arrived.
    @ObservationIgnored private var danglingRecords: Set<String> = []

    /// Created only when sync is used, so builds without the iCloud
    /// entitlement (tests, the Simulator) never touch CloudKit.
    @ObservationIgnored private var cachedCloud: CKContainer?
    private var cloud: CKContainer {
        if let cachedCloud { return cachedCloud }
        let container = CKContainer(identifier: Self.containerIdentifier)
        cachedCloud = container
        return container
    }

    var isEnabled: Bool { config != nil }

    private var context: ModelContext? { modelContainer?.mainContext }

    // MARK: - Lifecycle

    /// Resumes syncing if this phone is in a home. Call once at launch.
    func start(container: ModelContainer) {
        modelContainer = container
        config = Self.loadConfig()
        if config != nil { startEngine() }
    }

    /// The app came to the foreground: sync now and keep scanning.
    func sceneDidBecomeActive() {
        guard engine != nil else { return }
        startTimers()
        fetchNow()
    }

    /// The app is going away: push out anything pending.
    func sceneDidEnterBackground() {
        stopTimers()
        guard let engine else { return }
        scan()
        Task { try? await engine.sendChanges() }
    }

    func fetchNow() {
        guard let engine else { return }
        Task {
            do {
                try await engine.fetchChanges()
            } catch {
                status = .failed(Self.describe(error))
            }
        }
    }

    private func startEngine() {
        guard let config else { return }
        let database = config.role == .owner ? cloud.privateCloudDatabase : cloud.sharedCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: config.engineState,
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        status = .syncing
        UIApplication.shared.registerForRemoteNotifications()
        if UIApplication.shared.applicationState == .active { startTimers() }
        Task { await refreshMembers() }
    }

    /// Stops syncing. The inventory stays on this phone as its own copy.
    private func stopSync() {
        stopTimers()
        engine = nil
        config = nil
        members = []
        status = .off
        danglingRecords = []
        Self.saveConfig(nil)
        clearRecordStates()
    }

    private func startTimers() {
        stopTimers()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        fetchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchNow() }
        }
    }

    private func stopTimers() {
        scanTimer?.invalidate()
        fetchTimer?.invalidate()
        scanTimer = nil
        fetchTimer = nil
    }

    // MARK: - Owner

    /// Starts sharing this phone's inventory and returns the share to
    /// invite people with. Reuses the home and share if they exist.
    func prepareShare(homeName: String) async throws -> CKShare {
        if config == nil {
            try await requireAccount()
            let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
            let (saved, _) = try await cloud.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            if let result = saved[zoneID] { _ = try result.get() }
            clearRecordStates()
            config = Config(role: .owner, zoneName: zoneID.zoneName, zoneOwnerName: zoneID.ownerName, homeName: homeName, engineState: nil)
            Self.saveConfig(config)
            startEngine()
            scan()
        }
        guard let config, config.role == .owner else { throw HomeSyncError.alreadyInHome }
        if let existing = try await fetchShare() { return existing }

        let share = CKShare(recordZoneID: config.zoneID)
        share[CKShare.SystemFieldKey.title] = config.homeName
        share.publicPermission = .none
        let (saved, _) = try await cloud.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard let result = saved[share.recordID], let savedShare = try result.get() as? CKShare else {
            throw HomeSyncError.shareUnavailable
        }
        await refreshMembers()
        return savedShare
    }

    /// The container the sharing sheet talks to.
    var cloudContainer: CKContainer { cloud }

    /// Stops sharing and syncing. Everyone keeps a copy of the inventory as
    /// it is now; the other phones stop receiving updates.
    func stopSharing() async throws {
        guard let config, config.role == .owner else { return }
        do {
            _ = try await cloud.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [config.zoneID])
        } catch let error as CKError where error.code == .zoneNotFound {
            // Already gone.
        }
        stopSync()
    }

    // MARK: - Participant

    /// Called when the user taps an invitation link.
    func receive(_ metadata: CKShare.Metadata) {
        if let config, metadata.share.recordID.zoneID == config.zoneID {
            notice = "You're already in \(config.homeName)."
            return
        }
        pendingInvitation = metadata
    }

    /// Joins the home an invitation is for.
    /// - Parameter replacingLocalData: Start from the home's inventory
    ///   (true), or merge this phone's items into it (false).
    func accept(_ metadata: CKShare.Metadata, replacingLocalData: Bool) async throws {
        guard config == nil else { throw HomeSyncError.alreadyInHome }
        guard let context else { throw HomeSyncError.notSetUp }
        let share = try await acceptShare(metadata)
        if replacingLocalData {
            try InventoryStore(context: context).deleteAllData()
        }
        clearRecordStates()
        let zoneID = share.recordID.zoneID
        let title = share[CKShare.SystemFieldKey.title] as? String
        config = Config(
            role: .participant,
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            homeName: (title?.isEmpty == false ? title : nil) ?? "Shared home",
            engineState: nil,
            awaitingFirstFetch: true
        )
        Self.saveConfig(config)
        pendingInvitation = nil
        startEngine()
        fetchNow()
    }

    /// Leaves the home. This phone keeps a copy of the inventory.
    func leaveHome() async throws {
        guard let config, config.role == .participant else { return }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: config.zoneID)
        do {
            _ = try await cloud.sharedCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Already removed.
        }
        stopSync()
    }

    private func acceptShare(_ metadata: CKShare.Metadata) async throws -> CKShare {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let box = ShareBox()
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.perShareResultBlock = { _, result in
                if case .success(let share) = result { box.share = share }
            }
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    if let share = box.share {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: HomeSyncError.shareUnavailable)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    // MARK: - Members

    func fetchShare() async throws -> CKShare? {
        guard let config else { return nil }
        let database = config.role == .owner ? cloud.privateCloudDatabase : cloud.sharedCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: config.zoneID)
        do {
            return try await database.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func refreshMembers() async {
        guard let share = try? await fetchShare() else {
            members = []
            return
        }
        let formatter = PersonNameComponentsFormatter()
        members = share.participants.map { participant in
            let components = participant.userIdentity.nameComponents
            let name = components.map { formatter.string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? participant.userIdentity.lookupInfo?.emailAddress
                ?? "Invited person"
            return Member(
                id: participant.participantID,
                name: name,
                isOwner: participant.role == .owner,
                isPending: participant.acceptanceStatus == .pending
            )
        }
    }

    // MARK: - Finding local changes

    /// Compares every shared object with what iCloud last confirmed and
    /// queues uploads and deletions for the differences.
    func scan() {
        guard let engine, let config, let context, config.awaitingFirstFetch != true, !isApplyingRemote else { return }
        do {
            let states = try context.fetch(FetchDescriptor<SyncRecordState>())
            var byName: [String: SyncRecordState] = [:]
            for state in states { byName[state.recordName] = state }
            let agreed = byName.mapValues(\.payload)
            let current = try SyncMapper(context: context).snapshot(agreed: agreed.compactMapValues { $0 })
            let diff = SyncDiff.compute(current: current, agreed: agreed)
            guard !diff.saves.isEmpty || !diff.deletes.isEmpty else { return }

            var queuedSaves = Set<String>()
            var queuedDeletes = Set<String>()
            for change in engine.state.pendingRecordZoneChanges {
                switch change {
                case .saveRecord(let id): queuedSaves.insert(id.recordName)
                case .deleteRecord(let id): queuedDeletes.insert(id.recordName)
                @unknown default: break
                }
            }

            let now = Date()
            var changes: [CKSyncEngine.PendingRecordZoneChange] = []
            for name in diff.saves {
                let state: SyncRecordState
                if let existing = byName[name] {
                    state = existing
                } else {
                    state = SyncRecordState(recordName: name)
                    context.insert(state)
                }
                if state.changedAt == nil { state.changedAt = now }
                if !queuedSaves.contains(name) {
                    changes.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: config.zoneID)))
                }
            }
            var dropped: [CKSyncEngine.PendingRecordZoneChange] = []
            for name in diff.deletes {
                guard let state = byName[name] else { continue }
                let recordID = CKRecord.ID(recordName: name, zoneID: config.zoneID)
                if state.payload == nil && state.systemFields == nil {
                    // Never reached iCloud: nothing to delete there.
                    context.delete(state)
                    dropped.append(.saveRecord(recordID))
                } else if !queuedDeletes.contains(name) {
                    changes.append(.deleteRecord(recordID))
                }
            }
            if !dropped.isEmpty { engine.state.remove(pendingRecordZoneChanges: dropped) }
            if !changes.isEmpty { engine.state.add(pendingRecordZoneChanges: changes) }
            try context.save()
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    // MARK: - Applying remote changes

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        guard let context else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        let mapper = SyncMapper(context: context)

        let incoming = changes.modifications
            .map(\.record)
            .compactMap { record -> (CKRecord, Data, SyncEnvelope)? in
                guard record.recordType == Self.recordType,
                      let text = record["payload"] as? String,
                      let envelope = try? SyncEnvelope.decode(Data(text.utf8))
                else { return nil }
                return (record, Data(text.utf8), envelope)
            }
            .sorted { $0.2.kind.applyOrder < $1.2.kind.applyOrder }

        for (record, payload, envelope) in incoming {
            let state = recordState(envelope.recordName) ?? insertRecordState(envelope.recordName)
            state.systemFields = Self.encodeSystemFields(record)
            // A local edit that hasn't reached iCloud yet and is newer wins;
            // it goes up on the next send with the fresh change tag.
            if let changedAt = state.changedAt,
               SyncConflict.resolve(localChangedAt: changedAt, serverModifiedAt: record.modificationDate) == .keepLocal {
                state.payload = payload
                continue
            }
            do {
                let resolved = try mapper.apply(envelope)
                if !resolved { danglingRecords.insert(envelope.recordName) }
                state.payload = payload
                state.changedAt = nil
            } catch {
                status = .failed(Self.describe(error))
            }
        }

        for deletion in changes.deletions {
            let name = deletion.recordID.recordName
            guard let parsed = SyncRecordName.parse(name) else { continue }
            try? mapper.delete(kind: parsed.kind, id: parsed.id)
            if let state = recordState(name) { context.delete(state) }
        }
        try? context.save()
    }

    /// Re-applies records whose references arrived after them.
    private func resolveDanglingReferences() {
        guard let context, !danglingRecords.isEmpty else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        let mapper = SyncMapper(context: context)
        for name in danglingRecords {
            guard let payload = recordState(name)?.payload, let envelope = try? SyncEnvelope.decode(payload) else { continue }
            if (try? mapper.apply(envelope)) == true { danglingRecords.remove(name) }
        }
        try? context.save()
    }

    // MARK: - Sent changes

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        guard let context, let config else { return }
        for record in sent.savedRecords {
            let name = record.recordID.recordName
            let state = recordState(name) ?? insertRecordState(name)
            state.systemFields = Self.encodeSystemFields(record)
            if let text = record["payload"] as? String { state.payload = Data(text.utf8) }
            state.changedAt = nil
        }
        for recordID in sent.deletedRecordIDs {
            if let state = recordState(recordID.recordName) { context.delete(state) }
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            let name = recordID.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                let state = recordState(name) ?? insertRecordState(name)
                switch SyncConflict.resolve(localChangedAt: state.changedAt, serverModifiedAt: server.modificationDate) {
                case .takeServer:
                    applyServerRecord(server, state: state)
                case .keepLocal:
                    state.systemFields = Self.encodeSystemFields(server)
                    retry.append(.saveRecord(recordID))
                }
            case .unknownItem:
                // Deleted elsewhere while this phone changed it: put it back.
                recordState(name)?.systemFields = nil
                retry.append(.saveRecord(recordID))
            case .zoneNotFound:
                if config.role == .owner {
                    engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: config.zoneID))])
                    retry.append(.saveRecord(recordID))
                } else {
                    homeWasRemoved()
                    return
                }
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .requestRateLimited, .notAuthenticated, .operationCancelled:
                // CKSyncEngine retries these itself.
                break
            default:
                status = .failed(failure.error.localizedDescription)
            }
        }
        for (recordID, error) in sent.failedRecordDeletes where error.code == .unknownItem {
            // Already deleted, which is what we wanted.
            if let state = recordState(recordID.recordName) { context.delete(state) }
        }
        if !retry.isEmpty { engine?.state.add(pendingRecordZoneChanges: retry) }
        try? context.save()
    }

    private func applyServerRecord(_ record: CKRecord, state: SyncRecordState) {
        guard let context, let text = record["payload"] as? String, let envelope = try? SyncEnvelope.decode(Data(text.utf8)) else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        if (try? SyncMapper(context: context).apply(envelope)) == false {
            danglingRecords.insert(envelope.recordName)
        }
        state.payload = Data(text.utf8)
        state.systemFields = Self.encodeSystemFields(record)
        state.changedAt = nil
    }

    // MARK: - Home removed or account changed

    private func homeWasRemoved() {
        let name = config?.homeName ?? "The shared home"
        stopSync()
        notice = "\(name) is no longer shared with this phone. Your items are still here as your own copy."
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            break
        case .signOut, .switchAccounts:
            stopSync()
            notice = "iCloud signed out, so sharing stopped. Your items are still on this phone."
        @unknown default:
            break
        }
    }

    // MARK: - Record state

    private func recordState(_ name: String) -> SyncRecordState? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<SyncRecordState>(predicate: #Predicate<SyncRecordState> { state in state.recordName == name })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func insertRecordState(_ name: String) -> SyncRecordState {
        let state = SyncRecordState(recordName: name)
        context?.insert(state)
        return state
    }

    private func clearRecordStates() {
        guard let context else { return }
        for state in (try? context.fetch(FetchDescriptor<SyncRecordState>())) ?? [] {
            context.delete(state)
        }
        try? context.save()
    }

    /// Builds the CloudKit record for a pending save from the object as it
    /// is now. Returns nil (and drops the save) if the object is gone.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName
        guard let context, let parsed = SyncRecordName.parse(name) else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        let state = recordState(name)
        guard let payload = try? SyncMapper(context: context).payload(kind: parsed.kind, id: parsed.id, agreed: state?.payload) else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        let record = state?.systemFields.flatMap(Self.decodeSystemFields)
            ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record["kind"] = parsed.kind.rawValue
        record["payload"] = String(decoding: payload, as: UTF8.self)
        return record
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: - Account and errors

    private func requireAccount() async throws {
        let status = try await cloud.accountStatus()
        guard status == .available else { throw HomeSyncError.iCloudUnavailable(status) }
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud to keep syncing."
        case .networkFailure, .networkUnavailable: return "Offline. Changes will sync when you're back online."
        case .quotaExceeded: return "The home owner's iCloud storage is full."
        case .permissionFailure: return "iCloud sharing isn't set up for Larder yet."
        default: return error.localizedDescription
        }
    }

    // MARK: - Config storage

    private static var configURL: URL {
        URL.applicationSupportDirectory.appending(path: "HomeSync.json")
    }

    private static func loadConfig() -> Config? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    private static func saveConfig(_ config: Config?) {
        guard let config else {
            try? FileManager.default.removeItem(at: configURL)
            return
        }
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: configURL, options: .atomic)
    }
}

// MARK: - CKSyncEngineDelegate

extension HomeSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            config?.engineState = update.stateSerialization
            Self.saveConfig(config)
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            if let zoneID = config?.zoneID, changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                homeWasRemoved()
            }
        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes)
        case .sentRecordZoneChanges(let sent):
            handleSent(sent)
        case .willFetchChanges, .willSendChanges:
            status = .syncing
        case .didFetchChanges:
            if config?.awaitingFirstFetch == true {
                config?.awaitingFirstFetch = nil
                Self.saveConfig(config)
            }
            resolveDanglingReferences()
            scan()
            status = .upToDate(Date())
            await refreshMembers()
        case .didSendChanges:
            status = .upToDate(Date())
        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await self.record(for: recordID)
        }
    }
}

/// Carries the accepted share out of CloudKit's callback.
private final class ShareBox: @unchecked Sendable {
    var share: CKShare?
}
