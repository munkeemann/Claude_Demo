import InventoryCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingDelete = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                ClaudeSettingsSection()

                RemindersSettingsSection()

                Section("Inventory") {
                    NavigationLink {
                        LocationsSettingsView()
                    } label: {
                        Label("Storage Locations", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Button {
                        run("Sample data loaded.") { try $0.loadSampleData() }
                    } label: {
                        Label("Load Sample Data", systemImage: "tray.and.arrow.down")
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    if let statusMessage {
                        Text(statusMessage)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Self.appVersion)
                    LabeledContent("Core", value: InventoryCore.version)
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        Label("Product data: Open Food Facts (ODbL)", systemImage: "link")
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all products, items and history?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete All Data", role: .destructive) {
                    run("All data deleted.") { try $0.deleteAllData() }
                }
            } message: {
                Text("Storage locations are kept. This can't be undone.")
            }
            .errorAlert($errorMessage)
        }
    }

    private func run(_ successMessage: String, _ work: (InventoryStore) throws -> Void) {
        do {
            try work(InventoryStore(context: modelContext))
            statusMessage = successMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
