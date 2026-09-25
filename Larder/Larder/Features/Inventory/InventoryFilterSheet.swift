import InventoryCore
import SwiftUI

struct InventoryFilterSheet: View {
    @Binding var filter: InventoryFilter
    let locations: [StorageLocation]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort by") {
                    Picker("Sort by", selection: $filter.sort) {
                        ForEach(InventorySort.allCases) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Status") {
                    ForEach(ItemStatus.allCases) { status in
                        toggleRow(status.displayName, isOn: membership(status, in: \.statuses))
                    }
                }

                Section("Locations") {
                    ForEach(locations) { location in
                        toggleRow(location.name, systemImage: location.systemImage, isOn: membership(location.id, in: \.locationIDs))
                    }
                }

                Section("Food") {
                    ForEach(ProductCategory.foodCategories) { category in
                        toggleRow(category.displayName, systemImage: category.systemImage, isOn: membership(category, in: \.categories))
                    }
                }

                Section("Household") {
                    ForEach(ProductCategory.householdCategories) { category in
                        toggleRow(category.displayName, systemImage: category.systemImage, isOn: membership(category, in: \.categories))
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filter = InventoryFilter(searchText: filter.searchText)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggleRow(_ title: String, systemImage: String? = nil, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    /// A binding that adds/removes `element` from one of the filter's sets.
    private func membership<Element: Hashable>(
        _ element: Element,
        in keyPath: WritableKeyPath<InventoryFilter, Set<Element>>
    ) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: keyPath].contains(element) },
            set: { isMember in
                if isMember {
                    filter[keyPath: keyPath].insert(element)
                } else {
                    filter[keyPath: keyPath].remove(element)
                }
            }
        )
    }
}
