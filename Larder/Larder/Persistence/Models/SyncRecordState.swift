import Foundation
import SwiftData

/// What this phone last agreed with iCloud about one shared record. Local
/// bookkeeping only: it's never shared itself.
@Model
final class SyncRecordState {
    /// "<kind>.<UUID>", the CloudKit record name.
    var recordName: String = ""
    /// The payload iCloud confirmed last; nil while an upload is pending.
    var payload: Data?
    /// CloudKit's system fields (change tag and so on) for the record.
    var systemFields: Data?
    /// When this phone last changed the record, for resolving conflicts.
    var changedAt: Date?

    init(recordName: String) {
        self.recordName = recordName
    }
}
