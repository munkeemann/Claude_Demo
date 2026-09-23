import InventoryCore
import SwiftUI

/// Asks how much of an item was used, then logs a partial-use event.
struct UseSomeSheet: View {
    let item: InventoryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var amount: Double
    @State private var errorMessage: String?

    init(item: InventoryItem) {
        self.item = item
        _amount = State(initialValue: QuickActionCalculator.suggestedUseAmount(for: item.state))
    }

    private var step: Double { QuickActionCalculator.useStep(for: item.state) }
    private var maximum: Double { max(item.quantity, step) }
    private var remaining: Double { max(0, item.quantity - amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $amount, in: 0...maximum, step: step) {
                        HStack {
                            Text("Used")
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
                    if remaining <= 0 {
                        Text("That's all of it. The item will be marked used up.")
                    } else {
                        Text("\(item.unit.label(for: remaining)) left afterward.")
                    }
                }

                Section {
                    HStack {
                        ForEach([0.25, 0.5, 1.0], id: \.self) { fraction in
                            Button(fractionLabel(fraction)) {
                                amount = (item.quantity * fraction * 100).rounded() / 100
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                } header: {
                    Text("Quick amounts")
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { save() }
                        .disabled(amount <= 0)
                }
            }
            .errorAlert($errorMessage)
        }
        .presentationDetents([.medium, .large])
    }

    private func fractionLabel(_ fraction: Double) -> String {
        switch fraction {
        case 0.25: "¼"
        case 0.5: "½"
        default: "All"
        }
    }

    private func save() {
        do {
            try InventoryStore(context: modelContext).apply(.usedSome(amount), to: item)
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
                UseSomeSheet(item: item)
            }
        }
        .modelContainer(PreviewSupport.container)
}
