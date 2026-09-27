import Foundation
import SwiftData

/// A scanned receipt. Keeps the raw OCR text so it can be re-processed later.
@Model
final class Receipt {
    var id: UUID = UUID()
    var storeName: String?
    var purchaseDate: Date = Date()
    var totalCents: Int?
    var currencyCode: String = "USD"
    var rawText: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \PurchaseEvent.receipt)
    var purchases: [PurchaseEvent]? = []

    init(storeName: String?, purchaseDate: Date, totalCents: Int?, currencyCode: String, rawText: String, now: Date = Date()) {
        self.id = UUID()
        self.storeName = storeName
        self.purchaseDate = purchaseDate
        self.totalCents = totalCents
        self.currencyCode = currencyCode
        self.rawText = rawText
        self.createdAt = now
    }
}
