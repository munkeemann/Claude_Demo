import InventoryCore
import PhotosUI
import SwiftData
import SwiftUI

/// Photos of a shelf → Claude lists what's there → review → save. Adds
/// untracked products and updates counts of tracked ones in one go.
struct ShelfScanFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var locationID: UUID?
    @State private var stage: Stage = .chooseSource
    @State private var review: ShelfScanReview?
    /// A better-fitting location, when the photo shows a different kind of
    /// storage from the one picked (a fridge shot filed under Pantry).
    @State private var suggestedLocationID: UUID?
    @State private var photos: [UIImage] = []
    @State private var isShowingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var usedSample = false
    @State private var errorMessage: String?
    @State private var work: Task<Void, Never>?

    enum Stage: Equatable {
        case chooseSource
        case working(String)
        case review
        case datePass([UUID])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .chooseSource:
                    sourcePicker
                case .working(let message):
                    WorkingView(photos: photos, message: message)
                case .review:
                    if let binding = Binding($review) {
                        ShelfScanReviewView(review: binding, photos: photos, suggestion: suggestion, onImport: importReview)
                    }
                case .datePass(let ids):
                    DatePassView(itemIDs: ids) { dismiss() }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't read the shelf", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { stage = .chooseSource }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Scan a Shelf")
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
            }
        }
        .photoBatch($photos, pickerItems: $pickerItems, isShowingCamera: $isShowingCamera)
        .onAppear {
            if locationID == nil {
                locationID = (locations.first { $0.isBuiltIn && $0.kind == .pantry } ?? locations.first)?.id
            }
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
                        Text("Add your Anthropic API key in Settings to scan your own shelves. The sample works without one.")
                    } icon: {
                        Image(systemName: "key")
                    }
                    .foregroundStyle(Theme.honeyInk)
                }
            }

            Section {
                Picker("Location", selection: $locationID) {
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.systemImage).tag(Optional(location.id))
                    }
                }
            } footer: {
                Text("Larder compares the photos with what's already tracked here, so it can update counts instead of adding duplicates.")
            }

            PhotoBatchSection(
                photos: $photos,
                pickerItems: $pickerItems,
                isShowingCamera: $isShowingCamera,
                footer: "Take one photo per shelf, or the whole fridge in one shot, with labels facing out where you can. Photos are sent to Anthropic's Claude; nothing changes until you confirm."
            )

            Section {
                Button {
                    usedSample = true
                    photos = []
                    start(llm: environment.demoLLM)
                } label: {
                    Label("Try a Sample Shelf", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Shows a pre-computed scan of a pantry shelf.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !photos.isEmpty {
                Button {
                    usedSample = false
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

    // MARK: - Pipeline

    /// Prepares the photos, asks Claude what's on the shelf, then shows the
    /// review. With no photos (the sample), the demo service answers.
    private func start(llm: (any LLMService)? = nil) {
        work?.cancel()
        let service = llm ?? environment.llm
        let location = locations.first { $0.id == locationID }
        let images = photos
        work = Task {
            do {
                stage = .working(images.count > 1 ? "Preparing \(images.count) photos…" : "Preparing the photo…")
                let data = images.isEmpty ? [Data([0])] : PhotoBatch.jpegs(from: images)
                guard !data.isEmpty else {
                    stage = .failed("Those photos couldn't be prepared. Try others.")
                    return
                }
                let hints = try InventoryStore(context: modelContext).shelfScanHints(locationID: locationID)

                stage = .working("Looking over the shelf with Claude…")
                let input = ShelfScanInput(images: data, locationName: location?.name, climate: location?.climate, hints: hints)
                let result = try await service.scanShelf(input)
                try Task.checkCancellation()
                guard !result.items.isEmpty || !hints.isEmpty else {
                    stage = .failed("Claude didn't spot any groceries or household goods in these photos.")
                    return
                }
                review = ShelfScanReview(result: result, hints: hints, locationID: locationID)
                suggestedLocationID = result.mismatchedPlace(comparedTo: location?.climate).flatMap { place in
                    (locations.first(where: { $0.isBuiltIn && $0.climate == place }) ?? locations.first(where: { $0.climate == place }))?.id
                }
                stage = .review
            } catch is CancellationError {
                stage = .chooseSource
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }

    private var suggestion: ShelfScanReviewView.LocationSuggestion? {
        guard
            let suggested = locations.first(where: { $0.id == suggestedLocationID }),
            let picked = locations.first(where: { $0.id == locationID })
        else { return nil }
        return .init(name: suggested.name, systemImage: suggested.systemImage, pickedName: picked.name) {
            locationID = suggested.id
            suggestedLocationID = nil
            // Same photos, compared with what's tracked at the new location.
            start(llm: usedSample ? environment.demoLLM : nil)
        }
    }

    private func importReview() {
        guard let review else { return }
        let checkpoint = UndoCenter.checkpoint(modelContext)
        do {
            let added = try InventoryStore(context: modelContext).importShelfScan(review)
            let count = review.includedLines.count + review.unseen.filter(\.markFinished).count
            UndoCenter.shared.offer(count == 1 ? "Saved 1 change" : "Saved \(count) changes", checkpoint: checkpoint)
            finish(added: added)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Asks for package dates next when that's how this person likes it.
    private func finish(added: [InventoryItem]) {
        if ExpiryPreferences.mode == .scanDates, added.contains(where: DatePassView.usuallyDated) {
            stage = .datePass(added.map(\.id))
        } else {
            dismiss()
        }
    }
}

/// The photos being read, with a spinner.
struct WorkingView: View {
    var photos: [UIImage] = []
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            if let photo = photos.first {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if photos.count > 1 {
                            Text("+\(photos.count - 1)")
                                .font(.caption.weight(.semibold))
                                .padding(6)
                                .background(.regularMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
                    .padding(.horizontal)
            }
            ProgressView()
                .controlSize(.large)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ShelfScanFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
