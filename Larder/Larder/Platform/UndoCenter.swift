import Foundation
import InventoryCore
import Observation
import SwiftData

/// Offers "Undo" for a few seconds after a batch change (a receipt, a
/// shelf scan, a scan-out, a cooked recipe).
///
/// Before the change, a checkpoint records every shared record's payload,
/// the same snapshot household sync uses. Undo deletes the records the
/// change added and puts back the ones it changed, so it also syncs to the
/// rest of the home.
@Observable
@MainActor
final class UndoCenter {
    static let shared = UndoCenter()

    struct Offer: Identifiable {
        let id = UUID()
        let message: String
        let checkpoint: [String: Data]
    }

    private(set) var offer: Offer?
    private var expiry: Task<Void, Never>?

    /// The state to return to. Take it right before the change.
    static func checkpoint(_ context: ModelContext) -> [String: Data]? {
        try? SyncMapper(context: context).snapshot(agreed: [:])
    }

    /// Shows "message · Undo" for a few seconds.
    func offer(_ message: String, checkpoint: [String: Data]?) {
        guard let checkpoint else { return }
        let offer = Offer(message: message, checkpoint: checkpoint)
        self.offer = offer
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, self?.offer?.id == offer.id else { return }
            self?.offer = nil
        }
    }

    func dismiss() {
        expiry?.cancel()
        offer = nil
    }

    func undo(context: ModelContext) throws {
        guard let offer else { return }
        dismiss()
        try Self.restore(offer.checkpoint, context: context)
    }

    /// Returns the store to a checkpoint.
    static func restore(_ checkpoint: [String: Data], context: ModelContext) throws {
        let mapper = SyncMapper(context: context)
        let current = try mapper.snapshot(agreed: [:])
        // What the change added: events and items before what they point at.
        let added = current.keys
            .filter { checkpoint[$0] == nil }
            .compactMap(SyncRecordName.parse)
            .sorted { $0.kind.applyOrder > $1.kind.applyOrder }
        for record in added {
            try mapper.delete(kind: record.kind, id: record.id)
        }
        // What it changed or removed.
        let changed = checkpoint
            .filter { current[$0.key] != $0.value }
            .compactMap { try? SyncEnvelope.decode($0.value) }
            .sorted { $0.kind.applyOrder < $1.kind.applyOrder }
        for envelope in changed {
            try mapper.apply(envelope)
        }
        try context.save()
    }
}
