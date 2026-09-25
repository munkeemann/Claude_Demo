import InventoryCore
import SwiftUI

/// Scan (or type) a barcode → look it up locally, then in Open*Facts →
/// review in the item editor → save. Presented as a sheet.
struct ScanBarcodeFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment

    @State private var path: [ScanResult] = []
    @State private var manualCode = ""
    @State private var phase: Phase = .scanning

    enum Phase: Equatable {
        case scanning
        case lookingUp(String)
        case message(String)
    }

    struct ScanResult: Hashable {
        let id = UUID()
        let draft: ItemDraft
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                scanner
                manualEntry
            }
            .themedBackground()
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: ScanResult.self) { result in
                ItemEditorView(mode: .add(result.draft)) {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        ZStack(alignment: .bottom) {
            if BarcodeScannerView.isAvailable {
                BarcodeScannerView { code in
                    Task { await handle(code) }
                }
                .ignoresSafeArea(edges: .horizontal)
            } else {
                ContentUnavailableView(
                    "Camera scanning unavailable",
                    systemImage: "barcode.viewfinder",
                    description: Text("Live scanning needs a recent iPhone with camera access. Enter the barcode number below instead.")
                )
            }

            statusBanner
                .padding()
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .scanning:
            EmptyView()
        case .lookingUp(let code):
            HStack(spacing: 8) {
                ProgressView()
                Text("Looking up \(code)…")
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())
        case .message(let text):
            Text(text)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var manualEntry: some View {
        HStack {
            TextField("Barcode number", text: $manualCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { lookUpManualCode() }
            Button("Look Up") { lookUpManualCode() }
                .buttonStyle(.borderedProminent)
                .disabled(manualCode.filter(\.isNumber).count < 8 || isLookingUp)
        }
        .padding()
        .background(.bar)
    }

    private var isLookingUp: Bool {
        if case .lookingUp = phase { return true }
        return false
    }

    private func lookUpManualCode() {
        let code = manualCode
        Task { await handle(code) }
    }

    private func handle(_ rawCode: String) async {
        guard !isLookingUp, path.isEmpty else { return }
        let code = TextNormalizer.barcode(rawCode)
        guard code.count >= 8 else {
            phase = .message("That doesn't look like a product barcode.")
            return
        }
        let store = InventoryStore(context: modelContext)

        // Known locally: reuse the product without a network call.
        if let product = try? store.product(forBarcode: code),
           let item = product.items?.max(by: { $0.createdAt < $1.createdAt }) {
            show(item.restockDraft())
            return
        } else if let product = try? store.product(forBarcode: code) {
            show(ItemDraft(name: product.name, brand: product.brand ?? "", category: product.category,
                           unit: product.defaultUnit, barcode: code, packageSizeText: product.packageSizeText))
            return
        }

        phase = .lookingUp(code)
        do {
            if let result = try await environment.productLookup.lookup(barcode: code) {
                show(ItemDraft(lookup: result))
            } else {
                phase = .message("No product found for \(code). Fill in the details yourself.")
                show(ItemDraft(barcode: code))
            }
        } catch {
            phase = .message("Lookup failed (\(error.localizedDescription)). You can still add it by hand.")
            show(ItemDraft(barcode: code))
        }
    }

    private func show(_ draft: ItemDraft) {
        var draft = draft
        if draft.locationID == nil {
            draft.locationID = (try? InventoryStore(context: modelContext).defaultLocation(for: draft.category))?.id
        }
        if case .lookingUp = phase { phase = .scanning }
        path.append(ScanResult(draft: draft))
    }
}

#Preview {
    ScanBarcodeFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
