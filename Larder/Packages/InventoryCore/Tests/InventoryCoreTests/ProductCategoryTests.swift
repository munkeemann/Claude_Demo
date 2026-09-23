import Testing
@testable import InventoryCore

struct ProductCategoryTests {
    @Test func foodAndHouseholdPartitionAllCategories() {
        let food = Set(ProductCategory.foodCategories)
        let household = Set(ProductCategory.householdCategories)
        #expect(food.isDisjoint(with: household))
        #expect(food.union(household) == Set(ProductCategory.allCases))
    }

    @Test func householdGoodsAreNeverIngredientsOrExpiryTracked() {
        for category in ProductCategory.householdCategories {
            #expect(!category.defaultIsIngredient, "\(category)")
            #expect(!category.defaultTracksExpiry, "\(category)")
            #expect(category.defaultTracksRunOut, "\(category)")
        }
    }

    @Test func milkLikeDairyIsBothIngredientAndRunOutTracked() {
        #expect(ProductCategory.dairy.defaultIsIngredient)
        #expect(ProductCategory.dairy.defaultTracksRunOut)
        #expect(ProductCategory.dairy.defaultTracksExpiry)
    }

    @Test func defaultLocationMatchesDefaultClimate() {
        for category in ProductCategory.allCases {
            #expect(category.defaultLocationKind.defaultClimate == category.defaultClimate, "\(category)")
        }
    }

    @Test func builtInLocationsExcludeCustom() {
        #expect(!LocationKind.builtIn.contains(.custom))
        #expect(LocationKind.builtIn.count == 5)
    }
}
