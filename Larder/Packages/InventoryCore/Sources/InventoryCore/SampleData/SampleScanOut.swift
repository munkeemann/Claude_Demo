import Foundation

/// Canned scan-out and recipe-photo results for the offline demo. They name
/// items from `SampleData`, so the demo matches real rows.
public enum SampleScanOut {
    public static let result = ScanOutResult(items: [
        ScanOutItem(name: "Baby Spinach", brand: "Marketside"),
        ScanOutItem(name: "Roma Tomatoes", isAll: false, quantity: 2, unit: .each, confidence: .medium),
        ScanOutItem(name: "Plain Greek Yogurt", brand: "Fage"),
    ])

    public static let recipe = Recipe(
        title: "Spaghetti Marinara",
        summary: "Weeknight spaghetti in a garlicky tomato sauce.",
        mealType: .dinner,
        totalMinutes: 25,
        servings: 4,
        ingredients: [
            RecipeIngredient(name: "spaghetti", amount: "1 box"),
            RecipeIngredient(name: "marinara sauce", amount: "1 jar"),
            RecipeIngredient(name: "garlic", amount: "3 cloves"),
            RecipeIngredient(name: "olive oil", amount: "2 tbsp", isStaple: true),
            RecipeIngredient(name: "parmesan", amount: "1/2 cup"),
        ],
        steps: [
            "Boil the spaghetti in salted water until al dente.",
            "Warm the garlic in olive oil, then add the marinara and simmer.",
            "Toss the pasta with the sauce and top with parmesan.",
        ]
    )
}
