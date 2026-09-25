import InventoryCore
import SwiftData
import SwiftUI

/// Manage storage locations: reorder, add custom ones, rename, delete custom.
struct LocationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]
    @State private var editing: LocationEditorTarget?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(locations) { location in
                    Button {
                        editing = .existing(location)
                    } label: {
                        HStack {
                            Label(location.name, systemImage: location.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(location.climate.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .deleteDisabled(location.isBuiltIn)
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            } footer: {
                Text("The climate decides default shelf life for items stored here. Built-in locations can be renamed but not deleted.")
            }
        }
        .themedBackground()
        .navigationTitle("Storage Locations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("Add Location", systemImage: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editing) { target in
            LocationEditorSheet(target: target)
        }
        .errorAlert($errorMessage)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = locations
        ordered.move(fromOffsets: source, toOffset: destination)
        do {
            try InventoryStore(context: modelContext).reorderLocations(ordered)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let store = InventoryStore(context: modelContext)
        do {
            for index in offsets {
                try store.deleteLocation(locations[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum LocationEditorTarget: Identifiable {
    case new
    case existing(StorageLocation)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let location): location.id.uuidString
        }
    }
}

private struct LocationEditorSheet: View {
    let target: LocationEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var climate: StorageClimate
    @State private var systemImage: String
    @State private var errorMessage: String?

    static let icons = [
        "shippingbox", "cabinet", "refrigerator", "snowflake", "shower", "bubbles.and.sparkles",
        "house", "car", "wrench.and.screwdriver", "basket", "archivebox", "tray.2",
    ]

    init(target: LocationEditorTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: "")
            _climate = State(initialValue: .room)
            _systemImage = State(initialValue: "shippingbox")
        case .existing(let location):
            _name = State(initialValue: location.name)
            _climate = State(initialValue: location.climate)
            _systemImage = State(initialValue: location.systemImage)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Garage fridge)", text: $name)
                Picker("Climate", selection: $climate) {
                    ForEach(StorageClimate.allCases) { climate in
                        Text(climate.displayName).tag(climate)
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(
                                    icon == systemImage ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .onTapGesture { systemImage = icon }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .themedBackground()
            .navigationTitle(isNew ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() {
        do {
            switch target {
            case .new:
                try InventoryStore(context: modelContext).addLocation(name: trimmedName, climate: climate, systemImage: systemImage)
            case .existing(let location):
                location.name = trimmedName
                location.climate = climate
                location.systemImage = systemImage
                try modelContext.save()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        LocationsSettingsView()
    }
    .modelContainer(PreviewSupport.container)
}
