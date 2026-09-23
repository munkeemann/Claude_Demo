import InventoryCore
import PhotosUI
import SwiftData
import SwiftUI

/// Capture → OCR → Claude extraction → review → import. Presented as a sheet.
struct ReceiptScanFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var stage: Stage = .chooseSource
    @State private var review: ReceiptReview?
    @State private var isShowingCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pastedText = ""
    @State private var isPasting = false
    @State private var errorMessage: String?
    @State private var work: Task<Void, Never>?

    enum Stage: Equatable {
        case chooseSource
        case working(String)
        case review
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .chooseSource:
                    sourcePicker
                case .working(let message):
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    if let binding = Binding($review) {
                        ReceiptReviewView(review: binding, locations: locations, onImport: importReview)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't read the receipt", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { stage = .chooseSource }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        work?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            DocumentCameraView { images in
                isShowingCamera = false
                start { try await ReceiptTextRecognizer.text(from: images) }
            } onCancel: {
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPasting) {
            pasteSheet
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            start { try await Self.recognize(items) }
        }
        .interactiveDismissDisabled(stage == .review)
        .errorAlert($errorMessage)
    }

    // MARK: - Source picker

    private var sourcePicker: some View {
        List {
            if !environment.hasAPIKey {
                Section {
                    Label {
                        Text("Add your Anthropic API key in Settings to read your own receipts. The sample receipt works without one.")
                    } icon: {
                        Image(systemName: "key")
                    }
                    .foregroundStyle(.orange)
                }
            }

            Section {
                if DocumentCameraView.isAvailable {
                    Button { isShowingCamera = true } label: {
                        Label("Scan with Camera", systemImage: "doc.viewfinder")
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                    Label("Choose Photos", systemImage: "photo.on.rectangle")
                }
                Button { isPasting = true } label: {
                    Label("Paste Receipt Text", systemImage: "doc.on.clipboard")
                }
            } footer: {
                Text("Receipt text is sent to Anthropic's Claude to identify items. Nothing is added until you confirm.")
            }

            Section {
                Button {
                    start(llm: environment.hasAPIKey ? nil : environment.demoLLM) { SampleReceipt.ocrText }
                } label: {
                    Label("Try the Sample Receipt", systemImage: "wand.and.stars")
                }
            } footer: {
                if !environment.hasAPIKey {
                    Text("Without an API key the sample shows a pre-computed result.")
                }
            }
        }
    }

    private var pasteSheet: some View {
        NavigationStack {
            TextEditor(text: $pastedText)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal)
                .navigationTitle("Paste Receipt Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPasting = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Read") {
                            let text = pastedText
                            isPasting = false
                            start { text }
                        }
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }

    // MARK: - Pipeline

    /// Runs OCR (via `text`) and extraction, then shows the review.
    /// - Parameter llm: Overrides the configured service (offline demo).
    private func start(llm: (any LLMService)? = nil, text: @escaping () async throws -> String) {
        work?.cancel()
        let service = llm ?? environment.llm
        work = Task {
            do {
                stage = .working("Reading receipt…")
                let ocrText = try await text()
                guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    stage = .failed("No text was found. Try a sharper, well-lit photo.")
                    return
                }
                let store = InventoryStore(context: modelContext)
                let allHints = try store.receiptHints()
                let hints = ReceiptPrompt.relevantHints(for: ocrText, from: allHints)

                stage = .working("Identifying items with Claude…")
                let input = ReceiptExtractionInput(
                    ocrText: ocrText,
                    hints: hints,
                    today: Date(),
                    currencyCode: Locale.current.currency?.identifier ?? "USD"
                )
                let extraction = try await service.extractReceipt(input)
                try Task.checkCancellation()
                guard !extraction.items.isEmpty else {
                    stage = .failed("Claude didn't find any products on this receipt.")
                    return
                }

                var built = ReceiptReview(
                    extraction: extraction,
                    rawText: ocrText,
                    hints: allHints,
                    today: Date(),
                    defaultCurrency: input.currencyCode
                )
                for index in built.lines.indices {
                    built.lines[index].locationID = locationID(for: built.lines[index].locationKind)
                }
                review = built
                stage = .review
            } catch is CancellationError {
                stage = .chooseSource
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }

    private func locationID(for kind: LocationKind) -> UUID? {
        locations.first { $0.isBuiltIn && $0.kind == kind }?.id
    }

    private func importReview() {
        guard let review else { return }
        do {
            try InventoryStore(context: modelContext).importReceipt(review)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func recognize(_ items: [PhotosPickerItem]) async throws -> String {
        var images: [UIImage] = []
        for item in items {
            if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        return try await ReceiptTextRecognizer.text(from: images)
    }
}

#Preview {
    ReceiptScanFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
