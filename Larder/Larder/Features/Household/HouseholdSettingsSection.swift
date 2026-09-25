import CloudKit
import SwiftUI

/// Share the inventory with the people you live with, through iCloud.
struct HouseholdSettingsSection: View {
    @AppStorage("household.name") private var homeName = "Our Home"
    @State private var isWorking = false
    @State private var isConfirmingStop = false
    @State private var errorMessage: String?

    private var sync: HomeSync { .shared }

    var body: some View {
        Section {
            if let config = sync.config {
                LabeledContent("Home", value: config.homeName)
                statusRow
                ForEach(sync.members) { member in
                    Label {
                        HStack {
                            Text(member.name)
                            Spacer()
                            if member.isOwner {
                                TagBadge(text: "Owner", color: Theme.green)
                            } else if member.isPending {
                                TagBadge(text: "Invited")
                            }
                        }
                    } icon: {
                        Image(systemName: member.isOwner ? "house.fill" : "person.fill")
                            .foregroundStyle(Theme.green)
                    }
                }
                if config.role == .owner {
                    Button { invite() } label: {
                        Label("Invite or Manage People", systemImage: "person.badge.plus")
                    }
                    .disabled(isWorking)
                    Button(role: .destructive) { isConfirmingStop = true } label: {
                        Label("Stop Sharing", systemImage: "xmark.circle")
                    }
                } else {
                    Button(role: .destructive) { isConfirmingStop = true } label: {
                        Label("Leave This Home", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } else {
                TextField("Home name", text: $homeName)
                Button { invite() } label: {
                    HStack {
                        Label("Share Inventory…", systemImage: "person.2.fill")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isWorking || homeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Household")
        } footer: {
            Text(footer)
        }
        .confirmationDialog(
            sync.config?.role == .owner ? "Stop sharing this home?" : "Leave this home?",
            isPresented: $isConfirmingStop,
            titleVisibility: .visible
        ) {
            Button(sync.config?.role == .owner ? "Stop Sharing" : "Leave", role: .destructive) { stop() }
        } message: {
            Text("Everyone keeps a copy of the inventory as it is now, but changes stop syncing.")
        }
        .errorAlert($errorMessage)
        .task { await sync.refreshMembers() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sync.status {
        case .off:
            EmptyView()
        case .syncing:
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Syncing…")
                }
            }
        case .upToDate(let date):
            LabeledContent("Status") {
                Text("Up to date · \(date.formatted(.relative(presentation: .named)))")
            }
        case .failed(let message):
            LabeledContent("Status") {
                Text(message)
                    .foregroundStyle(Theme.terracotta)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var footer: String {
        switch sync.config?.role {
        case .owner:
            "Everyone in your home sees and edits the same inventory, shopping list and history. It lives in your iCloud."
        case .participant:
            "You're sharing this inventory. Changes sync through iCloud within seconds while the app is open."
        case nil:
            "Share one inventory with the people you live with. They get an invitation link, and everything syncs through iCloud. Everyone needs Larder on their iPhone."
        }
    }

    private func invite() {
        isWorking = true
        Task {
            do {
                let name = homeName.trimmingCharacters(in: .whitespaces)
                let share = try await sync.prepareShare(homeName: name.isEmpty ? "Our Home" : name)
                CloudSharing.present(share: share, container: sync.cloudContainer, title: sync.config?.homeName ?? name) {
                    Task { await sync.refreshMembers() }
                }
            } catch {
                errorMessage = HomeSync.describe(error)
            }
            isWorking = false
        }
    }

    private func stop() {
        isWorking = true
        Task {
            do {
                if sync.config?.role == .owner {
                    try await sync.stopSharing()
                } else {
                    try await sync.leaveHome()
                }
            } catch {
                errorMessage = HomeSync.describe(error)
            }
            isWorking = false
        }
    }
}
