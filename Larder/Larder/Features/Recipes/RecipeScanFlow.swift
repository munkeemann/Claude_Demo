import InventoryCore
import PhotosUI
import SwiftData
import SwiftUI

/// Photos of a recipe you cooked (a cookbook page, a card, a screenshot)
/// → Claude reads the ingredients and matches them to your inventory →
/// confirm how much of each you used → it comes off the inventory.
struct RecipeScanFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment

    @State private var photos: [UIImage] = []
    @State private var isShowingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var stage: Stage = .chooseSource
    @State private var work: Task<Void, Never>?

    enum Stage: Equatable {
        case chooseSource
        case working
        case cooked(EvaluatedRecipe)
        case failed(String)
    }

    var body: some View {
        if case .cooked(let evaluated) = stage {
            // Brings its own navigation and closes this whole sheet when done.
            CookedSheet(evaluated: evaluated) { _ in }
        } else {
            NavigationStack {
                Group {
                    switch stage {
                    case .chooseSource, .cooked:
                        sourcePicker
                    case .working:
                        WorkingView(photos: photos, message: "Reading the recipe…")
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn't use that recipe", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Try Again") { stage = .chooseSource }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .themedBackground()
                .navigationTitle("Scan a Recipe")
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
            .photoBatch($photos, pickerItems: $pickerItems, isShowingCamera: $isShowingCamera, maxCount: 4)
        }
    }

    private var sourcePicker: some View {
        List {
            if !environment.hasAPIKey {
                Section {
                    Label("Add your Anthropic API key in Settings to scan your own recipes. The sample works without one.", systemImage: "key")
                        .foregroundStyle(Theme.honeyInk)
                }
            }

            PhotoBatchSection(
                photos: $photos,
                pickerItems: $pickerItems,
                isShowingCamera: $isShowingCamera,
                maxCount: 4,
                footer: "Photograph the recipe you made, not the food: a cookbook page, a recipe card or a screenshot. Add a photo per page. You'll confirm how much of each ingredient you used."
            )

            Section {
                Button {
                    photos = []
                    start(llm: environment.demoLLM)
                } label: {
                    Label("Try a Sample Recipe", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Spaghetti marinara, matched against the sample data.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !photos.isEmpty {
                Button {
                    start()
                } label: {
                    Text("Read the Recipe").frame(maxWidth: .infinity)
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
        work = Task {
            do {
                stage = .working
                let request = try InventoryStore(context: modelContext).recipeRequest(filters: RecipeFilters())
                let data = images.isEmpty ? [Data([0])] : PhotoBatch.jpegs(from: images)
                let recipe = try await service.readRecipe(RecipeScanInput(images: data, items: request.items))
                try Task.checkCancellation()
                guard !RecipeScanPrompt.isEmpty(recipe) else {
                    stage = .failed("Claude couldn't find a recipe in these photos. Photograph the ingredient list.")
                    return
                }
                let evaluated = IngredientMatcher.evaluate(recipe, items: request.items, assumeStaples: true)
                guard !evaluated.usedItemIDs.isEmpty else {
                    stage = .failed("None of the ingredients in \(recipe.title) are in your inventory, so there's nothing to take off.")
                    return
                }
                stage = .cooked(evaluated)
            } catch is CancellationError {
                stage = .chooseSource
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }
}

#Preview {
    RecipeScanFlow()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
