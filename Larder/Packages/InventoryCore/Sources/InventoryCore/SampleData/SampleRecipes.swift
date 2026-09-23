import Foundation

/// Canned recipe suggestions matching `SampleData`, stored as the JSON Claude
/// returns. The ingredients carry no item ids, so they exercise local name
/// matching.
public enum SampleRecipes {
    public static let json = """
    {
      "recipes": [
        {
          "title": "Spinach & Cheddar Frittata",
          "summary": "Uses up the spinach before it wilts, plus eggs and cheddar you already have.",
          "mealType": "breakfast", "totalMinutes": 25, "servings": 4,
          "ingredients": [
            {"name": "eggs", "amount": "6", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "baby spinach", "amount": "4 cups", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "sharp cheddar cheese", "amount": "3 oz", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "yellow onion", "amount": "1", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "whole milk", "amount": "1/4 cup", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "olive oil", "amount": "1 tbsp", "inventoryItemId": null, "have": true, "isStaple": true},
            {"name": "salt", "amount": "to taste", "inventoryItemId": null, "have": true, "isStaple": true}
          ],
          "steps": [
            "Heat the oven to 375°F.",
            "Soften the diced onion in olive oil in an oven-safe skillet, about 5 minutes.",
            "Add the spinach and stir until wilted.",
            "Whisk the eggs with the milk, salt and half the cheddar; pour into the skillet.",
            "Top with the remaining cheddar and bake until set, 12–15 minutes."
          ]
        },
        {
          "title": "Garlicky Chicken & Tomato Spaghetti",
          "summary": "Cooks the chicken breast while it's fresh, with tomatoes, garlic and marinara.",
          "mealType": "dinner", "totalMinutes": 30, "servings": 4,
          "ingredients": [
            {"name": "spaghetti", "amount": "1 box", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "chicken breast", "amount": "1 lb", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "roma tomatoes", "amount": "3", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "garlic", "amount": "1", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "marinara sauce", "amount": "1 jar", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "parmesan cheese", "amount": "1/4 cup", "inventoryItemId": null, "have": false, "isStaple": false},
            {"name": "black pepper", "amount": "to taste", "inventoryItemId": null, "have": true, "isStaple": true}
          ],
          "steps": [
            "Boil the spaghetti in salted water until al dente.",
            "Slice the chicken and sear until cooked through; set aside.",
            "Sauté sliced garlic and chopped tomatoes for 3 minutes, then add the marinara.",
            "Toss the pasta and chicken in the sauce and finish with parmesan."
          ]
        },
        {
          "title": "Black Bean & Rice Bowls",
          "summary": "A pantry dinner from rice, beans and the last of the tomatoes.",
          "mealType": "lunch", "totalMinutes": 25, "servings": 3,
          "ingredients": [
            {"name": "jasmine rice", "amount": "1 cup", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "black beans", "amount": "1 can", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "roma tomato", "amount": "1", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "yellow onion", "amount": "1/2", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "cheddar cheese", "amount": "2 oz", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "lime", "amount": "1", "inventoryItemId": null, "have": false, "isStaple": false},
            {"name": "ground cumin", "amount": "1 tsp", "inventoryItemId": null, "have": true, "isStaple": true}
          ],
          "steps": [
            "Cook the rice.",
            "Warm the beans with the onion and cumin.",
            "Serve over rice topped with diced tomato, cheddar and a squeeze of lime."
          ]
        },
        {
          "title": "Banana Yogurt Smoothie",
          "summary": "Five minutes, and it uses bananas before they get too ripe.",
          "mealType": "snack", "totalMinutes": 5, "servings": 2,
          "ingredients": [
            {"name": "bananas", "amount": "2", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "greek yogurt", "amount": "6 oz", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "whole milk", "amount": "1/2 cup", "inventoryItemId": null, "have": true, "isStaple": false},
            {"name": "honey", "amount": "1 tbsp", "inventoryItemId": null, "have": false, "isStaple": false}
          ],
          "steps": [
            "Blend everything until smooth.",
            "Add a splash more milk if it's too thick."
          ]
        }
      ]
    }
    """

    public static let recipes: [Recipe] = {
        do {
            return try JSONDecoder().decode(RecipeResponse.self, from: Data(json.utf8)).recipes
        } catch {
            preconditionFailure("SampleRecipes.json is invalid: \(error)")
        }
    }()
}
