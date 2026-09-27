import InventoryCore
import SwiftData
import SwiftUI

/// Type or dictate a list ("milk, a dozen eggs, 2 lb chicken thighs") and
/// add it all at once. Claude reads the list when there's a key; otherwise
/// it's parsed on the phone.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment

    @State private var text = ""
    @State private var stage: Stage = .entry
    @State private var review: ShelfScanReview?
    @State private var errorMessage: String?
    @State private var work: Task<Void, Never>?
    @FocusState private var isEditing: Bool

    enum Stage: Equatable {
        case entry
        case working
        case review
        case datePass([UUID])
    }

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:
                    entry
                case .working:
                    WorkingView(message: "Reading your list…")
                case .review:
                    if let binding = Binding($review) {
                        ShelfScanReviewView(review: binding, finder: environment.hasAPIKey ? "Claude" : "Larder", onImport: importReview)
                    }
                case .datePass(let ids):
                    DatePassView(itemIDs: ids) { dismiss() }
                }
            }
            .themedBackground()
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .datePass = stage {
                        EmptyView()
                    } else {
                        Button("Cancel") {
                            work?.cancel()
                            dismiss()
                        }
                    }
                }
                if stage == .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit List") { stage = .entry }
                    }
                }
            }
        }
        .interactiveDismissDisabled(stage == .review || hasText)
        .errorAlert($errorMessage)
    }

    private var entry: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("milk, a dozen eggs, 2 lb chicken thighs, bananas, paper towels…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .focused($isEditing)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                }
            } footer: {
                Text("One item per line or separated by commas. Tap the microphone on the keyboard to say the list instead. \(environment.hasAPIKey ? "Claude sorts out names, amounts and where each thing goes." : "Add a Claude key in Settings for smarter reading of long or spoken lists.")")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: read) {
                Text("Review Items").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasText)
            .padding()
            .background(.bar)
        }
        .onAppear { isEditing = true }
    }

    private func read() {
        isEditing = false
        let list = text
        let useClaude = environment.hasAPIKey
        let llm = environment.llm
        stage = .working
        work = Task {
            var items: [QuickAddItem]
            if useClaude {
                do {
                    items = try await llm.parseQuickAdd(list).items
                } catch is CancellationError {
                    stage = .entry
                    return
                } catch {
                    // Still useful offline: fall back to reading it here.
                    items = QuickAddParser.parse(list)
                }
            } else {
                items = QuickAddParser.parse(list)
            }
            guard !Task.isCancelled else { return }
            guard !items.isEmpty else {
                errorMessage = "Couldn't find any items in that list."
                stage = .entry
                return
            }
            do {
                let lines = try InventoryStore(context: modelContext).quickAddLines(items)
                review = ShelfScanReview(lines: lines, locationID: nil, source: .manual, justBought: true)
                stage = .review
            } catch {
                errorMessage = error.localizedDescription
                stage = .entry
            }
        }
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

#Preview {
    QuickAddView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
