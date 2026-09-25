import InventoryCore
import SwiftData
import SwiftUI

/// Ask Claude for recipes built around what's in stock, expiring items first.
struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query(
        filter: #Predicate<SavedRecipe> { saved in saved.isFavorite == true },
        sort: \SavedRecipe.createdAt,
        order: .reverse
    ) private var favorites: [SavedRecipe]
    // Observed so favorites re-evaluate against current stock.
    @Query private var items: [InventoryItem]

    @State private var filters = RecipeFilters()
    @State private var phase: Phase = .idle
    @State private var work: Task<Void, Never>?

    enum Phase {
        case idle
        case loading
        case results([EvaluatedRecipe], usedDemo: Bool)
        case failed(String)
    }

    private var store: InventoryStore { InventoryStore(context: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                filterSection

                Section {
                    Button {
                        suggest()
                    } label: {
                        HStack {
                            Label("Suggest Recipes", systemImage: "sparkles")
                            if case .loading = phase {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading)
                } footer: {
                    Text(environment.hasAPIKey
                         ? "Sends your ingredient list to Claude. Items expiring soonest are prioritized."
                         : "No API key yet, so you'll see sample recipes. Add a key in Settings for real suggestions.")
                }

                resultsSection

                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { saved in
                            if let recipe = saved.recipe {
                                let evaluated = evaluate(recipe.withoutInventoryReferences)
                                NavigationLink {
                                    RecipeDetailView(evaluated: evaluated)
                                } label: {
                                    RecipeRow(evaluated: evaluated, subtitle: cookedSubtitle(saved))
                                }
                            }
                        }
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Recipes")
        }
    }

    // MARK: - Sections

    private var filterSection: some View {
        Section("What are you after?") {
            Picker("Meal", selection: $filters.mealType) {
                ForEach(MealType.allCases) { meal in
                    Text(meal.displayName).tag(meal)
                }
            }
            Picker("Time", selection: $filters.maxMinutes) {
                Text("Any").tag(Int?.none)
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Text("\(minutes) min or less").tag(Optional(minutes))
                }
            }
            Picker("Ingredients", selection: $filters.maxMissing) {
                Text("Only what I have").tag(0)
                Text("Missing up to 1").tag(1)
                Text("Missing up to 2").tag(2)
                Text("Missing up to 3").tag(3)
            }
            Toggle("Assume pantry staples", isOn: $filters.assumeStaples)
            TextField("Preferences (e.g. vegetarian, no nuts)", text: $filters.preferences)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch phase {
        case .idle, .loading:
            EmptyView()
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.honeyInk)
            }
        case .results(let recipes, let usedDemo):
            Section {
                if recipes.isEmpty {
                    Text("No recipes fit these filters. Try allowing a missing ingredient or more time.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recipes) { evaluated in
                    NavigationLink {
                        RecipeDetailView(evaluated: evaluated)
                    } label: {
                        RecipeRow(evaluated: evaluated, subtitle: nil)
                    }
                }
            } header: {
                Text(usedDemo ? "Sample suggestions" : "Suggestions")
            }
        }
    }

    // MARK: - Actions

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func suggest() {
        work?.cancel()
        let usedDemo = !environment.hasAPIKey
        let service = usedDemo ? environment.demoLLM : environment.llm
        let filters = filters
        phase = .loading
        work = Task {
            do {
                let request = try store.recipeRequest(filters: filters)
                guard !request.items.isEmpty else {
                    phase = .failed("There are no ingredients in stock yet. Add some food first.")
                    return
                }
                let recipes = try await service.suggestRecipes(request)
                try Task.checkCancellation()
                let evaluated = recipes.map {
                    IngredientMatcher.evaluate($0, items: request.items, assumeStaples: filters.assumeStaples)
                }
                phase = .results(RecipeRanking.rank(evaluated, filters: filters), usedDemo: usedDemo)
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-matches a saved recipe against current stock.
    private func evaluate(_ recipe: Recipe) -> EvaluatedRecipe {
        let request = (try? store.recipeRequest(filters: filters)) ?? RecipeRequest(items: [], filters: filters)
        return IngredientMatcher.evaluate(recipe, items: request.items, assumeStaples: filters.assumeStaples)
    }

    private func cookedSubtitle(_ saved: SavedRecipe) -> String? {
        guard let last = saved.lastCookedAt else { return nil }
        let times = saved.timesCooked == 1 ? "once" : "\(saved.timesCooked) times"
        return "Cooked \(times), last \(last.formatted(.relative(presentation: .named)))"
    }
}

struct RecipeRow: View {
    let evaluated: EvaluatedRecipe
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(evaluated.recipe.title)
                .font(.headline)
            HStack(spacing: 10) {
                if evaluated.recipe.totalMinutes > 0 {
                    Label("\(evaluated.recipe.totalMinutes) min", systemImage: "clock")
                }
                Label("\(evaluated.recipe.servings)", systemImage: "person.2")
                if evaluated.missingCount == 0 {
                    Label("Have everything", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.green)
                } else {
                    Label("\(evaluated.missingCount) missing", systemImage: "cart")
                        .foregroundStyle(Theme.honeyInk)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !evaluated.expiringItemNames.isEmpty {
                Label("Uses \(evaluated.expiringItemNames.joined(separator: ", "))", systemImage: "leaf")
                    .font(.caption)
                    .foregroundStyle(Theme.green)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    RecipesView()
        .modelContainer(PreviewSupport.container)
        .environment(AppEnvironment.preview())
}
