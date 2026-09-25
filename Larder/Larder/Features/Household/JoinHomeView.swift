import CloudKit
import SwiftUI

/// Shown when someone taps a household invitation.
struct JoinHomeView: View {
    let metadata: CKShare.Metadata

    @Environment(\.dismiss) private var dismiss
    @State private var replaceLocal = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    private var homeName: String {
        (metadata.share[CKShare.SystemFieldKey.title] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "a shared home"
    }

    private var ownerName: String? {
        metadata.ownerIdentity.nameComponents.map { PersonNameComponentsFormatter().string(from: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandCard {
                        HStack(spacing: 14) {
                            LarderMark(size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Join \(homeName)")
                                    .font(.title3.weight(.bold))
                                if let ownerName, !ownerName.isEmpty {
                                    Text("Shared by \(ownerName)")
                                        .font(.subheadline)
                                        .opacity(0.85)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Items on this phone", selection: $replaceLocal) {
                        Text("Use the shared inventory").tag(true)
                        Text("Add mine to it").tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Items already on this phone")
                } footer: {
                    Text(replaceLocal
                        ? "This phone's current items are replaced by the shared inventory. Storage locations are kept."
                        : "This phone's items are added to the shared inventory. Matching products and locations are combined.")
                }

                Section {
                    Text("Everyone in the home sees and edits the same items, shopping list and history, synced through iCloud. Reminders and your Claude API key stay per phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .themedBackground()
            .navigationTitle("Household Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        HomeSync.shared.pendingInvitation = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button("Join") { join() }
                    }
                }
            }
            .errorAlert($errorMessage)
        }
        .interactiveDismissDisabled(isJoining)
    }

    private func join() {
        isJoining = true
        Task {
            do {
                try await HomeSync.shared.accept(metadata, replacingLocalData: replaceLocal)
                dismiss()
            } catch {
                errorMessage = HomeSync.describe(error)
            }
            isJoining = false
        }
    }
}
