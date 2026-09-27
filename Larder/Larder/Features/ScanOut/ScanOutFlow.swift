import InventoryCore
import PhotosUI
import SwiftData
import SwiftUI

/// Photos of things leaving the house (thrown away, or used up and headed
/// for the recycling) → Claude matches them to the inventory → review →
/// they're marked tossed or used. Good for clearing out the fridge.
struct ScanOutFlow: View {
    var initialDisposition: ScanOutDisposition = .tossed

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment

    @State private var disposition: ScanOutDisposition = .tossed
    @State private var stage: Stage = .chooseSource
    @State private var review: ScanOutReview?
    @State private var photos: [UIImage] = []
    @State private var isShowingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var work: Task<Void, Never>?

    enum Stage: Equatable {
        case chooseSource
        case working
        case review
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .chooseSource:
                    sourcePicker
                case .working:
                    WorkingView(photos: photos, message: "Matching with your inventory…")
                case .review:
                    if let binding = Binding($review) {
                        ScanOutReviewView(review: binding, photos: photos, onApply: apply)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't read the photos", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { stage = .chooseSource }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .themedBackground()
            .navigationTitle(disposition == .tossed ? "Toss Things Out" : "Used Things Up")
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
        .photoBatch($photos, pickerItems: $pickerItems, isShowingCamera: $isShowingCamera)
        .onAppear { disposition = initialDisposition }
        .interactiveDismissDisabled(stage == .review)
        .errorAlert($errorMessage)
    }

    private var sourcePicker: some View {
        List {
            if !environment.hasAPIKey {
                Section {
                    Label("Add your Anthropic API key in Settings to scan your own photos. The sample works without one.", systemImage: "key")
                        .foregroundStyle(Theme.honeyInk)
                }
            }

            Section {
                Picker("These are", selection: $disposition) {
                    Text("Being thrown out").tag(ScanOutDisposition.tossed)
                    Text("Used up").tag(ScanOutDisposition.used)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(disposition == .tossed
                    ? "Tossed food counts as waste, not as eating it, so it doesn't speed up \"running low\" estimates."
                    : "Used-up items count toward how fast you go through things.")
            }

            PhotoBatchSection(
                photos: $photos,
                pickerItems: $pickerItems,
                isShowingCamera: $isShowingCamera,
                footer: "Lay things out on the counter, or take a photo of each. Claude matches what it sees to your inventory; nothing changes until you confirm."
            )

            Section {
                Button {
                    photos = []
                    start(llm: environment.demoLLM)
                } label: {
                    Label("Try a Sample", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Shows a pre-computed scan that matches the sample data.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !photos.isEmpty {
                Button {
                    start()
                } label: {
                    Text(photos.count == 1 ? "Scan 1 Photo" : "Scan \(photos.count) Photos")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!environment.hasAPIKey)
                .padding()
                .background(.bar)
            }
        }
    }

    private func start(llm: (any LLMService)? = nil) {
        work?.cancel()
        let service = llm ?? environment.llm
        let images = photos
        let disposition = disposition
        work = Task {
            do {
                stage = .working
                let data = images.isEmpty ? [Data([0])] : PhotoBatch.jpegs(from: images)
                let hints = try InventoryStore(context: modelContext).scanOutHints()
                let result = try await service.scanOut(ScanOutInput(images: data, disposition: disposition, hints: hints))
                try Task.checkCancellation()
                guard !result.items.isEmpty else {
                    stage = .failed("Claude didn't spot anything in these photos.")
                    return
                }
                review = ScanOutReview(result: result, hints: hints, disposition: disposition)
                stage = .review
            } catch is CancellationError {
                stage = .chooseSource
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }

    private func apply() {
        guard let review else { return }
        let checkpoint = UndoCenter.checkpoint(modelContext)
        do {
            let count = try InventoryStore(context: modelContext).applyScanOut(review)
            let verb = review.includedLines.allSatisfy { $0.disposition == .tossed } ? "Tossed" : "Updated"
            UndoCenter.shared.offer(count == 1 ? "\(verb) 1 item" : "\(verb) \(count) items", checkpoint: checkpoint)
            let context = modelContext
            Task { await Reminders.refresh(context: context) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Which inventory items leave, and how.
struct ScanOutReviewView: View {
    @Binding var review: ScanOutReview
    var photos: [UIImage] = []
    var onApply: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.createdAt, order: .reverse) private var allItems: [InventoryItem]

    private var activeItems: [InventoryItem] { allItems.filter(\.status.isActive) }
    private var matched: [ScanOutLine] { review.lines.filter { $0.matchedItemID != nil } }
    private var unmatched: [ScanOutLine] { review.lines.filter { $0.matchedItemID == nil } }

    var body: some View {
        List {
            Section {
                Picker("Mark all as", selection: Binding(
                    get: { review.lines.first?.disposition ?? .tossed },
                    set: { review.setDisposition($0) }
                )) {
                    ForEach(ScanOutDisposition.allCases) { disposition in
                        Text(disposition.label).tag(disposition)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Change single items by tapping them.")
            }

            if !matched.isEmpty {
                Section("From your inventory") {
                    ForEach($review.lines) { $line in
                        if line.matchedItemID != nil {
                            HStack(spacing: 8) {
                                IncludeToggle(isOn: $line.include)
                                NavigationLink {
                                    ScanOutLineEditor(line: $line, items: activeItems)
                                } label: {
                                    ScanOutLineRow(line: line, item: item(line.matchedItemID))
                                }
                            }
                        }
                    }
                }
            }

            if !unmatched.isEmpty {
                Section {
                    ForEach($review.lines) { $line in
                        if line.matchedItemID == nil {
                            NavigationLink {
                                ScanOutLineEditor(line: $line, items: activeItems)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.name)
                                    Text("Tap to pick the item it is")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Not matched")
                } footer: {
                    Text("Claude couldn't tie these to something in your inventory. They're left alone unless you pick an item.")
                }
            }
        }
        .themedBackground()
        .safeAreaInset(edge: .bottom) {
            Button(action: onApply) {
                let count = review.includedLines.count
                Text(count == 1 ? "Update 1 Item" : "Update \(count) Items")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!review.canApply)
            .padding()
            .background(.bar)
        }
    }

    private func item(_ id: UUID?) -> InventoryItem? {
        guard let id else { return nil }
        return allItems.first { $0.id == id }
    }
}

private struct ScanOutLineRow: View {
    let line: ScanOutLine
    let item: InventoryItem?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item?.product?.category ?? .other, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item?.displayName ?? line.name)
                        .strikethrough(!line.include)
                    if line.confidence == .low {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.honeyInk)
                            .accessibilityLabel("Low confidence")
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(line.disposition.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(line.disposition == .tossed ? Theme.terracotta : Theme.green)
        }
        .opacity(line.include ? 1 : 0.6)
    }

    private var detail: String {
        guard let item else { return line.name }
        let amount = line.amount.map { "\(item.unit.label(for: $0)) of \(item.quantityLabel)" } ?? "All \(item.quantityLabel)"
        return [amount, item.location?.name].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ScanOutLineEditor: View {
    @Binding var line: ScanOutLine
    let items: [InventoryItem]

    private var item: InventoryItem? { items.first { $0.id == line.matchedItemID } }

    var body: some View {
        Form {
            Section {
                Picker("Item", selection: Binding(
                    get: { line.matchedItemID },
                    set: { id in
                        line.matchedItemID = id
                        line.amount = nil
                        line.include = id != nil
                    }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(items) { item in
                        Text("\(item.displayName) · \(item.location?.name ?? "No location")").tag(Optional(item.id))
                    }
                }
            } header: {
                Text("Claude saw “\(line.name)”")
            }

            if let item {
                Section {
                    Picker("What happened", selection: $line.disposition) {
                        ForEach(ScanOutDisposition.allCases) { disposition in
                            Text(disposition.label).tag(disposition)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("All of it", isOn: Binding(
                        get: { line.amount == nil },
                        set: { line.amount = $0 ? nil : QuickActionCalculator.suggestedUseAmount(for: item.state) }
                    ))
                    .tint(Theme.green)
                    if let amount = line.amount {
                        Stepper(
                            value: Binding(get: { amount }, set: { line.amount = $0 }),
                            in: 0...max(item.quantity, 0.01),
                            step: QuickActionCalculator.useStep(for: item.state)
                        ) {
                            Text("\(item.unit.label(for: amount)) of \(item.quantityLabel)")
                        }
                    }
                } footer: {
                    Text(line.disposition == .tossed ? "Counts as waste." : "Counts as eating or using it.")
                }
            }
        }
        .themedBackground()
        .navigationTitle(item?.displayName ?? line.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ScanOutFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
