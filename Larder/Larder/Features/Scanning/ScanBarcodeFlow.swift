import InventoryCore
import SwiftData
import SwiftUI

/// Scan barcode after barcode without stopping, then review them all at
/// once. Each code is looked up while you keep scanning: first among
/// products you've had, then in Open Food Facts. Unknown ones can be
/// identified from a photo of the package.
struct ScanBarcodeFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment

    @State private var scanned: [Scanned] = []
    @State private var manualCode = ""
    @State private var stage: Stage = .scanning
    @State private var review: ShelfScanReview?
    @State private var photographing: Scanned.ID?
    @State private var errorMessage: String?

    enum Stage: Equatable {
        case scanning
        case review
        case datePass([UUID])
    }

    struct Scanned: Identifiable, Equatable {
        enum Status: Equatable {
            case lookingUp
            case found
            case unknown
            case identifying
        }

        let id = UUID()
        let code: String
        var count = 1
        var state: Status = .lookingUp
        var line: ShelfScanLine?
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .scanning:
                    VStack(spacing: 0) {
                        scanner
                        tray
                        manualEntry
                    }
                case .review:
                    if let binding = Binding($review) {
                        ShelfScanReviewView(review: binding, finder: "Larder", onImport: importReview)
                    }
                case .datePass(let ids):
                    DatePassView(itemIDs: ids) { dismiss() }
                }
            }
            .themedBackground()
            .navigationTitle("Scan Barcodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    switch stage {
                    case .scanning: Button("Cancel") { dismiss() }
                    case .review: Button("Scan More") { stage = .scanning }
                    case .datePass: EmptyView()
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { photographing != nil }, set: { if !$0 { photographing = nil } })) {
            CameraPicker { image in
                let id = photographing
                photographing = nil
                if let id { identify(id, from: image) }
            } onCancel: {
                photographing = nil
            }
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled(!scanned.isEmpty)
        .errorAlert($errorMessage)
    }

    // MARK: - Scanning

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            if BarcodeScannerView.isAvailable {
                BarcodeScannerView { code in
                    add(code)
                }
                .ignoresSafeArea(edges: .horizontal)
            } else {
                ContentUnavailableView(
                    "Camera scanning unavailable",
                    systemImage: "barcode.viewfinder",
                    description: Text("Live scanning needs a recent iPhone with camera access. Enter barcode numbers below instead.")
                )
            }
            Text(scanned.isEmpty ? "Scan one item after another" : "Keep scanning, or review below")
                .font(.subheadline)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding()
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var tray: some View {
        if !scanned.isEmpty {
            VStack(spacing: 0) {
                List {
                    ForEach($scanned) { $entry in
                        TrayRow(entry: $entry, canIdentify: environment.hasAPIKey && CameraPicker.isAvailable) {
                            photographing = entry.id
                        }
                    }
                    .onDelete { scanned.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(scanned.count) * 58, 232))

                Button {
                    showReview()
                } label: {
                    Text(reviewTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(scanned.contains { $0.state == .lookingUp || $0.state == .identifying })
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .background(.bar)
        }
    }

    private var reviewTitle: String {
        let total = scanned.reduce(0) { $0 + $1.count }
        return total == 1 ? "Review 1 Item" : "Review \(total) Items"
    }

    private var manualEntry: some View {
        HStack {
            TextField("Barcode number", text: $manualCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(addManualCode)
            Button("Add", action: addManualCode)
                .buttonStyle(.bordered)
                .disabled(manualCode.filter(\.isNumber).count < 8)
        }
        .padding()
        .background(.bar)
    }

    private func addManualCode() {
        add(manualCode)
        manualCode = ""
    }

    /// A new code joins the tray; the same code again adds one more.
    private func add(_ rawCode: String) {
        let code = TextNormalizer.barcode(rawCode)
        guard code.count >= 8 else {
            errorMessage = "That doesn't look like a product barcode."
            return
        }
        if let index = scanned.firstIndex(where: { $0.code == code }) {
            scanned[index].count += 1
            return
        }
        let entry = Scanned(code: code)
        scanned.append(entry)
        Task { await lookUp(entry.id, code: code) }
    }

    private func lookUp(_ id: Scanned.ID, code: String) async {
        let store = InventoryStore(context: modelContext)
        var line: ShelfScanLine?
        if let product = try? store.product(forBarcode: code) {
            // A product you've had: same amount and place as last time.
            let last = product.items?.max { $0.createdAt < $1.createdAt }
            line = ShelfScanLine(
                name: product.name,
                brand: product.brand ?? "",
                category: product.category,
                quantity: last?.initialQuantity ?? 1,
                unit: last?.unit ?? product.defaultUnit,
                packageSize: product.packageSizeText,
                locationID: last?.location?.id ?? (try? store.defaultLocation(for: product.category))?.id,
                barcode: code
            )
        } else if let result = try? await environment.productLookup.lookup(barcode: code) {
            let draft = ItemDraft(lookup: result)
            line = ShelfScanLine(
                name: draft.name,
                brand: draft.brand,
                category: draft.category,
                quantity: draft.quantity,
                unit: draft.unit,
                packageSize: draft.packageSizeText,
                locationID: (try? store.defaultLocation(for: draft.category))?.id,
                barcode: code,
                imageURL: draft.imageURL
            )
        }
        guard let index = scanned.firstIndex(where: { $0.id == id }) else { return }
        scanned[index].line = line
        scanned[index].state = line == nil ? .unknown : .found
    }

    /// Reads an unknown product off a photo of its package.
    private func identify(_ id: Scanned.ID, from image: UIImage) {
        guard let index = scanned.firstIndex(where: { $0.id == id }), let jpeg = ShelfPhoto.jpegData(from: image) else { return }
        scanned[index].state = .identifying
        let code = scanned[index].code
        let llm = environment.llm
        Task {
            let result = try? await llm.scanShelf(ShelfScanInput(image: jpeg))
            guard let index = scanned.firstIndex(where: { $0.id == id }) else { return }
            if let item = result?.items.max(by: { rank($0.confidence) < rank($1.confidence) }) {
                scanned[index].line = ShelfScanLine(
                    name: item.name,
                    brand: item.brand ?? "",
                    category: item.category,
                    quantity: 1,
                    unit: item.unit.isDiscrete ? item.unit : .each,
                    packageSize: item.packageSize,
                    shelfLifeDays: item.shelfLifeDays,
                    locationID: (try? InventoryStore(context: modelContext).defaultLocation(for: item.category))?.id,
                    barcode: code
                )
                scanned[index].state = .found
            } else {
                scanned[index].state = .unknown
                errorMessage = "Claude couldn't make out the product. You can type its name in the review."
            }
        }
    }

    private func rank(_ confidence: ExtractionConfidence) -> Int {
        switch confidence {
        case .high: 2
        case .medium: 1
        case .low: 0
        }
    }

    // MARK: - Review

    private func showReview() {
        let lines = scanned.map { entry -> ShelfScanLine in
            var line = entry.line ?? ShelfScanLine(include: false, name: "", category: .other, quantity: 1, unit: .each, barcode: entry.code)
            line.quantity *= Double(entry.count)
            return line
        }
        review = ShelfScanReview(lines: lines, locationID: nil, source: .barcode, justBought: true)
        stage = .review
    }

    private func importReview() {
        guard let review else { return }
        let checkpoint = UndoCenter.checkpoint(modelContext)
        do {
            let added = try InventoryStore(context: modelContext).importShelfScan(review)
            UndoCenter.shared.offer(added.count == 1 ? "Added 1 item" : "Added \(added.count) items", checkpoint: checkpoint)
            if ExpiryPreferences.mode == .scanDates, added.contains(where: DatePassView.usuallyDated) {
                stage = .datePass(added.map(\.id))
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrayRow: View {
    @Binding var entry: ScanBarcodeFlow.Scanned
    let canIdentify: Bool
    var onPhotograph: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch entry.state {
            case .lookingUp, .identifying:
                ProgressView()
                    .frame(width: 30)
            case .found:
                CategoryIcon(category: entry.line?.category ?? .other, size: 30)
            case .unknown:
                Image(systemName: "questionmark.square.dashed")
                    .font(.title2)
                    .foregroundStyle(Theme.honeyInk)
                    .frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                Text(entry.code)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.state == .unknown, canIdentify {
                Button("Photo", systemImage: "camera", action: onPhotograph)
                    .buttonStyle(.bordered)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Identify from a photo")
            }
            Stepper("", value: $entry.count, in: 1...99)
                .labelsHidden()
                .fixedSize()
            Text("\(entry.count)")
                .monospacedDigit()
                .frame(minWidth: 18)
        }
    }

    private var title: String {
        switch entry.state {
        case .lookingUp: "Looking up…"
        case .identifying: "Reading the package…"
        case .unknown: "Unknown product"
        case .found: entry.line.map { $0.brand.isEmpty ? $0.name : "\($0.name) · \($0.brand)" } ?? "Unknown product"
        }
    }
}

#Preview {
    ScanBarcodeFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
