import InventoryCore
import PhotosUI
import SwiftData
import SwiftUI

/// Photo of a shelf → Claude lists what's there → review → save. Adds
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
    @State private var photo: UIImage?
    @State private var isShowingCamera = false
    @State private var photoItem: PhotosPickerItem?
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
                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal)
                        }
                        ProgressView()
                            .controlSize(.large)
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    if let binding = Binding($review) {
                        ShelfScanReviewView(review: binding, photo: photo, suggestion: suggestion, onImport: importReview)
                    }
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
                    Button("Cancel") {
                        work?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                start(image: image)
            } onCancel: {
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    start(image: image)
                } else {
                    errorMessage = "That photo couldn't be opened."
                }
            }
        }
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
                Text("Larder compares the photo with what's already tracked here, so it can update counts instead of adding duplicates.")
            }

            Section {
                if CameraPicker.isAvailable {
                    Button { isShowingCamera = true } label: {
                        Label("Take a Photo", systemImage: "camera")
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose a Photo", systemImage: "photo")
                }
            } footer: {
                Text("Get a whole shelf or the inside of the fridge in one shot, with labels facing out where you can. The photo is sent to Anthropic's Claude; nothing changes until you confirm.")
            }

            Section {
                Button {
                    start(image: nil, llm: environment.demoLLM)
                } label: {
                    Label("Try a Sample Shelf", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Shows a pre-computed scan of a pantry shelf.")
            }
        }
    }

    // MARK: - Pipeline

    /// Prepares the photo, asks Claude what's on the shelf, then shows the
    /// review. With no image (the sample), the demo service answers.
    private func start(image: UIImage?, llm: (any LLMService)? = nil) {
        work?.cancel()
        photo = image
        let service = llm ?? environment.llm
        let location = locations.first { $0.id == locationID }
        work = Task {
            do {
                stage = .working("Preparing the photo…")
                let data: Data
                if let image {
                    guard let jpeg = ShelfPhoto.jpegData(from: image) else {
                        stage = .failed("That photo couldn't be prepared. Try another.")
                        return
                    }
                    data = jpeg
                } else {
                    // The demo service ignores the image.
                    data = Data([0])
                }
                let hints = try InventoryStore(context: modelContext).shelfScanHints(locationID: locationID)

                stage = .working("Looking over the shelf with Claude…")
                let input = ShelfScanInput(image: data, locationName: location?.name, climate: location?.climate, hints: hints)
                let result = try await service.scanShelf(input)
                try Task.checkCancellation()
                guard !result.items.isEmpty || !hints.isEmpty else {
                    stage = .failed("Claude didn't spot any groceries or household goods in this photo.")
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
            // Same photo, compared with what's tracked at the new location.
            start(image: photo, llm: photo == nil ? environment.demoLLM : nil)
        }
    }

    private func importReview() {
        guard let review else { return }
        do {
            try InventoryStore(context: modelContext).importShelfScan(review)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ShelfScanFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
