import Foundation
import InventoryCore
import SwiftData
import Testing
@testable import Larder

/// Two in-memory "phones" exchanging records through the mapper, the way
/// HomeSync does through CloudKit.
@MainActor
struct SyncMapperTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    let phoneA: ModelContainer
    let phoneB: ModelContainer

    init() throws {
        phoneA = try Persistence.makeContainer(inMemory: true)
        phoneB = try Persistence.makeContainer(inMemory: true)
    }

    func store(_ container: ModelContainer) -> InventoryStore {
        InventoryStore(context: container.mainContext, now: { Self.now })
    }

    func mapper(_ container: ModelContainer) -> SyncMapper {
        SyncMapper(context: container.mainContext)
    }

    /// Sends every record from `source` to `destination`, in apply order.
    func transfer(from source: ModelContainer, to destination: ModelContainer) throws -> [String: Data] {
        let payloads = try mapper(source).snapshot(agreed: [:])
        let envelopes = try payloads.values
            .map { try SyncEnvelope.decode($0) }
            .sorted { $0.kind.applyOrder < $1.kind.applyOrder }
        for envelope in envelopes {
            try mapper(destination).apply(envelope)
        }
        try destination.mainContext.save()
        return payloads
    }

    @Test func everyRecordRoundTripsExactly() throws {
        try store(phoneA).loadSampleData()
        let sent = try transfer(from: phoneA, to: phoneB)
        #expect(sent.count > 20)
        let received = try mapper(phoneB).snapshot(agreed: [:])
        #expect(Set(received.keys) == Set(sent.keys))
        let mismatched = sent.keys.filter { received[$0] != sent[$0] }
        #expect(mismatched.isEmpty, "Payloads changed in transit: \(mismatched.sorted().prefix(5))")
    }

    @Test func joiningAdoptsBuiltInLocationsInsteadOfDuplicating() throws {
        try store(phoneA).seedLocationsIfNeeded()
        try store(phoneB).seedLocationsIfNeeded()
        let fridgeB = try #require(try store(phoneB).locations().first { $0.kind == .fridge })
        let milk = try store(phoneB).addItem(
            from: ItemDraft(name: "Milk", category: .dairy, locationID: fridgeB.id, purchaseDate: Self.now),
            source: .manual
        )

        _ = try transfer(from: phoneA, to: phoneB)

        let locations = try store(phoneB).locations()
        #expect(locations.count == LocationKind.builtIn.count)
        let fridgeA = try #require(try store(phoneA).locations().first { $0.kind == .fridge })
        #expect(milk.location?.id == fridgeA.id)
    }

    @Test func joiningMergesSameNamedProducts() throws {
        try store(phoneA).addItem(from: ItemDraft(name: "Whole Milk", category: .dairy, purchaseDate: Self.now), source: .receipt)
        let local = try store(phoneB).addItem(from: ItemDraft(name: "whole milk", category: .dairy, purchaseDate: Self.now), source: .receipt)

        _ = try transfer(from: phoneA, to: phoneB)

        let products = try phoneB.mainContext.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let shared = try #require(try phoneA.mainContext.fetch(FetchDescriptor<Product>()).first)
        #expect(products.first?.id == shared.id)
        #expect(local.product?.id == shared.id)
        #expect((products.first?.purchases ?? []).count == 2)
    }

    @Test func referencesResolveWhenTheTargetArrivesLater() throws {
        let item = try store(phoneA).addItem(from: ItemDraft(name: "Eggs", category: .eggs, purchaseDate: Self.now), source: .manual)
        let productID = try #require(item.product?.id)
        let itemEnvelope = try #require(try mapper(phoneA).envelope(kind: .item, id: item.id))
        let productEnvelope = try #require(try mapper(phoneA).envelope(kind: .product, id: productID))

        #expect(try mapper(phoneB).apply(itemEnvelope) == false)
        let received = try #require(try mapper(phoneB).item(item.id))
        #expect(received.product == nil)

        try mapper(phoneB).apply(productEnvelope)
        #expect(try mapper(phoneB).apply(itemEnvelope) == true)
        #expect(received.product?.id == productID)
    }

    @Test func unresolvedReferencesAreKeptInThePayload() throws {
        let item = try store(phoneA).addItem(from: ItemDraft(name: "Eggs", category: .eggs, purchaseDate: Self.now), source: .manual)
        let sent = try #require(try mapper(phoneA).envelope(kind: .item, id: item.id))
        try mapper(phoneB).apply(sent)
        let agreed = try sent.encoded()

        // The product hasn't arrived, so phone B must not report the item as changed.
        let payload = try mapper(phoneB).payload(kind: .item, id: item.id, agreed: agreed)
        #expect(payload == agreed)
    }

    @Test func deletesRemoveTheObject() throws {
        let item = try store(phoneA).addItem(from: ItemDraft(name: "Bread", category: .bakery, purchaseDate: Self.now), source: .manual)
        _ = try transfer(from: phoneA, to: phoneB)
        #expect(try mapper(phoneB).item(item.id) != nil)

        try mapper(phoneB).delete(kind: .item, id: item.id)
        try phoneB.mainContext.save()
        #expect(try mapper(phoneB).item(item.id) == nil)
        let names = try mapper(phoneB).snapshot(agreed: [:]).keys
        #expect(!names.contains(SyncRecordName.make(.item, item.id)))
    }

    @Test func missingFieldsLeaveLocalValuesAlone() throws {
        let item = try store(phoneA).addItem(from: ItemDraft(name: "Rice", category: .grains, purchaseDate: Self.now, notes: "top shelf"), source: .manual)
        _ = try transfer(from: phoneA, to: phoneB)

        // A sender that doesn't know about "notes" (an older version) sends a quantity change.
        var partial = try #require(try mapper(phoneA).envelope(kind: .item, id: item.id))
        partial.fields["notes"] = nil
        partial.fields["quantity"] = .number(0.5)
        try mapper(phoneB).apply(partial)

        let received = try #require(try mapper(phoneB).item(item.id))
        #expect(received.quantity == 0.5)
        #expect(received.notes == "top shelf")
    }
}
