import Foundation
import Testing
@testable import InventoryCore

struct SyncTests {
    let productID = UUID()
    let itemID = UUID()

    @Test func recordNamesRoundTrip() throws {
        let name = SyncRecordName.make(.item, itemID)
        #expect(name == "item.\(itemID.uuidString)")
        let parsed = try #require(SyncRecordName.parse(name))
        #expect(parsed.kind == .item)
        #expect(parsed.id == itemID)
        #expect(SyncRecordName.parse("cloudkit.zoneshare") == nil)
        #expect(SyncRecordName.parse("gadget.\(itemID.uuidString)") == nil)
        #expect(SyncRecordName.parse("item.not-a-uuid") == nil)
    }

    @Test func applyOrderPutsReferencedKindsFirst() {
        #expect(SyncKind.location.applyOrder < SyncKind.item.applyOrder)
        #expect(SyncKind.product.applyOrder < SyncKind.alias.applyOrder)
        #expect(SyncKind.receipt.applyOrder < SyncKind.purchase.applyOrder)
        #expect(SyncKind.item.applyOrder < SyncKind.usage.applyOrder)
    }

    @Test func fieldsRoundTripExactly() throws {
        let date = Date(timeIntervalSinceReferenceDate: 811_692_800.123456789)
        var writer = SyncFieldWriter()
        writer.set("name", "Whole Milk")
        writer.set("brand", nil as String?)
        writer.set("quantity", 0.333333333333)
        writer.set("days", 7)
        writer.set("flag", true)
        writer.set("when", date)
        writer.set("never", nil as Date?)
        writer.set("blob", Data([1, 2, 3]))

        let envelope = SyncEnvelope(kind: .product, id: productID, fields: writer.fields)
        let decoded = try SyncEnvelope.decode(try envelope.encoded())
        #expect(decoded == envelope)

        let reader = SyncFieldReader(decoded.fields)
        #expect(reader.string("name") == "Whole Milk")
        #expect(reader.has("brand") && reader.string("brand") == nil)
        #expect(!reader.has("missing"))
        #expect(reader.double("quantity") == 0.333333333333)
        #expect(reader.int("days") == 7)
        #expect(reader.bool("flag") == true)
        #expect(reader.date("when") == date)
        #expect(reader.has("never") && reader.date("never") == nil)
        #expect(reader.data("blob") == Data([1, 2, 3]))
    }

    @Test func encodingIsCanonical() throws {
        var first = SyncFieldWriter()
        first.set("a", "1")
        first.set("b", 2.5)
        var second = SyncFieldWriter()
        second.set("b", 2.5)
        second.set("a", "1")
        let one = SyncEnvelope(kind: .item, id: itemID, fields: first.fields, refs: ["product": SyncRef(.product, productID)])
        let two = SyncEnvelope(kind: .item, id: itemID, fields: second.fields, refs: ["product": SyncRef(.product, productID)])
        #expect(try one.encoded() == two.encoded())
        // A decoded copy re-encodes to the same bytes.
        #expect(try SyncEnvelope.decode(one.encoded()).encoded() == one.encoded())
    }

    @Test func preservesFieldsFromNewerVersions() {
        let previous = SyncEnvelope(kind: .item, id: itemID, fields: ["notes": "old", "futureField": "keep me"])
        let current = SyncEnvelope(kind: .item, id: itemID, fields: ["notes": "new"])
        let merged = current.preserving(from: previous) { _ in true }
        #expect(merged.fields["notes"] == "new")
        #expect(merged.fields["futureField"] == "keep me")
    }

    @Test func preservesReferencesThatHaventArrivedYet() {
        let product = SyncRef(.product, productID)
        let location = SyncRef(.location, UUID())
        let previous = SyncEnvelope(kind: .item, id: itemID, refs: ["product": product, "location": location])
        let current = SyncEnvelope(kind: .item, id: itemID)
        // The product isn't on this phone yet; the location is, and was cleared on purpose.
        let merged = current.preserving(from: previous) { $0 == location }
        #expect(merged.refs["product"] == product)
        #expect(merged.refs["location"] == nil)
    }

    @Test func preservingIgnoresOtherRecords() {
        let previous = SyncEnvelope(kind: .item, id: UUID(), fields: ["x": 1])
        let current = SyncEnvelope(kind: .item, id: itemID)
        #expect(current.preserving(from: previous) { _ in false } == current)
        #expect(current.preserving(from: nil) { _ in false } == current)
    }

    @Test func diffFindsNewChangedAndDeletedRecords() {
        let same = Data("same".utf8)
        let result = SyncDiff.compute(
            current: [
                "item.unchanged": same,
                "item.changed": Data("new".utf8),
                "item.new": Data("n".utf8),
                "item.queued": Data("q".utf8),
            ],
            agreed: [
                "item.unchanged": same,
                "item.changed": Data("old".utf8),
                "item.queued": Data?.none,
                "item.gone": Data("g".utf8),
            ]
        )
        #expect(result.saves == ["item.changed", "item.new", "item.queued"])
        #expect(result.deletes == ["item.gone"])
    }

    @Test func laterChangeWinsConflicts() {
        let earlier = Date(timeIntervalSinceReferenceDate: 100)
        let later = Date(timeIntervalSinceReferenceDate: 200)
        #expect(SyncConflict.resolve(localChangedAt: later, serverModifiedAt: earlier) == .keepLocal)
        #expect(SyncConflict.resolve(localChangedAt: earlier, serverModifiedAt: later) == .takeServer)
        #expect(SyncConflict.resolve(localChangedAt: nil, serverModifiedAt: later) == .takeServer)
        #expect(SyncConflict.resolve(localChangedAt: earlier, serverModifiedAt: nil) == .keepLocal)
    }
}
