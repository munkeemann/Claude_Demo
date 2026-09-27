import InventoryCore
import SwiftData
import SwiftUI
import VisionKit

/// Reads the date off a package with the live camera. Text is recognized
/// on the phone (no Claude call) and parsed by `PrintedDateParser`.
struct DateScannerView: UIViewControllerRepresentable {
    var onDate: (PrintedDate) -> Void

    @MainActor
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onDate = onDate
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDate: onDate)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onDate: (PrintedDate) -> Void
        private var last: Date?

        init(onDate: @escaping (PrintedDate) -> Void) {
            self.onDate = onDate
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            read(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            read(allItems)
        }

        private func read(_ items: [RecognizedItem]) {
            let text = items.compactMap { item -> String? in
                if case .text(let text) = item { return text.transcript }
                return nil
            }.joined(separator: "\n")
            guard let found = PrintedDateParser.parse(text, now: Date(), dayFirst: DateOrder.dayFirst), found.date != last else { return }
            last = found.date
            UISelectionFeedbackGenerator().selectionChanged()
            onDate(found)
        }
    }
}

enum DateOrder {
    /// Whether this region writes the day before the month (05/06 = 5 June).
    static var dayFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "MMdd", options: 0, locale: .current) ?? "MM/dd"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return false }
        return day < month
    }
}

/// Point the camera at a package date, or pick it by hand.
struct DateCaptureView: View {
    let title: String
    var initial: Date?
    var onSave: (Date) -> Void
    var onSkip: (() -> Void)?

    @State private var found: PrintedDate?
    @State private var manual: Date
    @State private var isPickingManually = false

    init(title: String, initial: Date? = nil, onSave: @escaping (Date) -> Void, onSkip: (() -> Void)? = nil) {
        self.title = title
        self.initial = initial
        self.onSave = onSave
        self.onSkip = onSkip
        _manual = State(initialValue: initial ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _isPickingManually = State(initialValue: !DateScannerView.isAvailable)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isPickingManually {
                Form {
                    Section {
                        DatePicker("Date on the package", selection: $manual, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    } footer: {
                        if !DateScannerView.isAvailable {
                            Text("Reading dates with the camera needs a recent iPhone.")
                        }
                    }
                }
                .themedBackground()
            } else {
                ZStack(alignment: .bottom) {
                    DateScannerView { date in
                        withAnimation { found = date }
                    }
                    .ignoresSafeArea(edges: .horizontal)
                    Text(found == nil ? "Point at the \"best by\" or \"use by\" date" : "Hold steady, or tap Use This Date")
                        .font(.subheadline)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
            }

            VStack(spacing: 10) {
                if let found, !isPickingManually {
                    Button {
                        onSave(found.date)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Use This Date")
                                .font(.headline)
                            Text("\(found.kind.label) \(found.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if isPickingManually {
                    Button {
                        onSave(manual)
                    } label: {
                        Text("Save Date").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                HStack {
                    if DateScannerView.isAvailable {
                        Button(isPickingManually ? "Use the Camera" : "Enter by Hand") {
                            isPickingManually.toggle()
                        }
                    }
                    Spacer()
                    if let onSkip {
                        Button("Skip", action: onSkip)
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// After adding a batch, walks through the new items that usually have a
/// date on the package, one at a time. Skipped items keep their estimate.
struct DatePassView: View {
    let itemIDs: [UUID]
    var onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var index = 0
    @State private var saved = 0

    /// Items worth asking about: packaged food with no date yet.
    private var items: [InventoryItem] {
        let store = InventoryStore(context: modelContext)
        return itemIDs.compactMap { try? store.item(id: $0) }.filter(Self.usuallyDated)
    }

    static func usuallyDated(_ item: InventoryItem) -> Bool {
        guard item.printedExpiryDate == nil, let category = item.product?.category else { return false }
        let dated: Set<ProductCategory> = [.dairy, .cheese, .eggs, .deli, .meat, .seafood, .bakery, .canned, .condiments, .snacks, .beverages, .frozen, .grains, .baby]
        return dated.contains(category)
    }

    var body: some View {
        let queue = items
        Group {
            if index < queue.count {
                let item = queue[index]
                DateCaptureView(title: "\(index + 1) of \(queue.count): \(item.displayName)") { date in
                    save(date, for: item)
                } onSkip: {
                    index += 1
                }
                .id(item.id)
            } else {
                ContentUnavailableView {
                    Label(saved == 0 ? "No dates added" : (saved == 1 ? "1 date added" : "\(saved) dates added"), systemImage: "calendar.badge.checkmark")
                } description: {
                    Text("Items without a package date use Larder's estimate. You can add a date to any item later.")
                } actions: {
                    Button("Done", action: onFinish)
                        .buttonStyle(.borderedProminent)
                }
                .themedBackground()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if index < queue.count {
                    Button("Finish", action: onFinish)
                }
            }
        }
    }

    private func save(_ date: Date, for item: InventoryItem) {
        try? InventoryStore(context: modelContext).setPackageDate(item, date)
        saved += 1
        index += 1
    }
}
