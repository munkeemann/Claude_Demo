import InventoryCore
import SwiftUI

/// "How much is left?" Sets an item's amount without logging usage, which
/// resets the forecast's projection for it.
struct RecountSheet: View {
    let item: InventoryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var amount: Double
    @State private var errorMessage: String?

    /// - Parameter suggested: The estimate to start from, if there is one.
    init(item: InventoryItem, suggested: Double? = nil) {
        self.item = item
        _amount = State(initialValue: suggested ?? item.quantity)
    }

    private var full: Double { max(item.initialQuantity, item.quantity) }
    private var step: Double { QuickActionCalculator.useStep(for: item.state) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $amount, in: 0...max(full, amount, step), step: step) {
                        HStack {
                            Text("Left")
                            Spacer()
                            TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                            Text(item.unit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(amount <= 0
                        ? "The item will be marked used up."
                        : "Larder estimates use from here, so a quick check now and then keeps predictions accurate.")
                }

                Section("Quick amounts") {
                    HStack {
                        ForEach([1.0, 0.75, 0.5, 0.25, 0], id: \.self) { fraction in
                            Button(Self.label(fraction)) {
                                amount = (full * fraction * 100).rounded() / 100
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .themedBackground()
            .navigationTitle("How much is left?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .errorAlert($errorMessage)
        }
        .presentationDetents([.medium, .large])
    }

    static func label(_ fraction: Double) -> String {
        switch fraction {
        case 1: "Full"
        case 0.75: "¾"
        case 0.5: "½"
        case 0.25: "¼"
        default: "None"
        }
    }

    private func save() {
        do {
            try InventoryStore(context: modelContext).recount(item, quantity: amount)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    Text("Preview host")
        .sheet(isPresented: .constant(true)) {
            if let item = PreviewSupport.firstItem(named: "Whole Milk") {
                RecountSheet(item: item, suggested: 0.4)
            }
        }
        .modelContainer(PreviewSupport.container)
}
