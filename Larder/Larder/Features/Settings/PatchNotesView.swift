import SwiftUI

/// What changed in each update, newest first.
struct PatchNotesView: View {
    struct Release: Identifiable {
        var id: String { title }
        let title: String
        let date: String
        let notes: [String]
    }

    static let releases: [Release] = [
        Release(title: "Scan things out, smarter dates", date: "September 27, 2026", notes: [
            "Scan things out: photograph what you're throwing away or finished, several photos at a time for a fridge clean-out, and Larder takes it off your inventory. Tossed food counts as waste, not as eating it.",
            "Photograph a recipe you cooked and Larder takes the ingredients off your inventory.",
            "Quick Add: type or say a list (\"milk, a dozen eggs, 2 lb chicken thighs\") and add it all at once.",
            "Barcode scanning keeps going: scan package after package, then review them together. Unknown barcodes can be identified from a photo of the package.",
            "Shelf scans take several photos at once.",
            "Pick your usual way of adding in Settings. Tap + to use it; hold + for the others.",
            "Review screens: tap the circle to skip an item without opening it.",
            "Expiry dates now come from USDA FoodKeeper storage times for 661 foods: pantry, fridge and freezer, after opening and after thawing.",
            "New household setting for how cautious to be with dates, from Very cautious to Very relaxed. Meat, poultry, seafood, deli, dairy, leftovers and baby food never go past USDA's longest time.",
            "New personal setting: estimate dates, scan package dates, or leave them blank. Package dates can be read with the camera.",
            "Larder tracks when things are opened, and asks when you move something from the pantry to the fridge.",
            "Freeze it: move something to the freezer from the item, the list, or an expiry reminder, and its date resets to USDA's freezer time.",
            "Expiry reminders offer Freeze It and Find a Recipe.",
            "The Soon tab shows what you threw out this month and roughly what it cost.",
            "Undo after saving a batch.",
            "Siri and Shortcuts: \"Add to Larder\", \"Used something up in Larder\", \"What's expiring in Larder\".",
            "These patch notes.",
        ]),
        Release(title: "Green dark mode", date: "September 26, 2026", notes: [
            "In dark mode, pages use the logo's green, with cream headings.",
        ]),
        Release(title: "Better shelf scans", date: "September 26, 2026", notes: [
            "Shelf scans list everything in the photo, fridge doors full of condiments included, instead of only what Claude was sure of.",
            "If the photo looks like the fridge but you picked the pantry, the review offers to scan again for the right place.",
            "The review shows how many products were found.",
        ]),
        Release(title: "Households, usage estimates and a new look", date: "September 26, 2026", notes: [
            "Share one inventory with everyone at home through iCloud.",
            "Scan a whole shelf or the fridge with one photo.",
            "Larder learns how fast you use things from your purchases and tells you when you're getting low, even for things you never log.",
            "Reminders to toss things that are past their date, with a \"Tossed them\" button.",
            "Colors and type to match the app icon.",
            "New builds reach TestFlight automatically.",
        ]),
        Release(title: "First TestFlight build", date: "September 2026", notes: [
            "Inventory by storage location, receipt scanning, barcode lookup, expiry and run-out reminders, recipe suggestions and a shopping list.",
        ]),
    ]

    var body: some View {
        List {
            Section {
                LabeledContent("This version", value: SettingsView.appVersion)
            }
            ForEach(Self.releases) { release in
                Section {
                    ForEach(release.notes, id: \.self) { note in
                        Text(note)
                            .font(.subheadline)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(release.title)
                            .font(.headline)
                            .foregroundStyle(Theme.heading)
                            .textCase(nil)
                        Text(release.date)
                            .textCase(nil)
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Patch Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PatchNotesView()
    }
}
