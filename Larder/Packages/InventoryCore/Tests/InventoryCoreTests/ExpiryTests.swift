import Foundation
import Testing
@testable import InventoryCore

struct FoodKeeperTests {
    @Test func bundledDataDecodes() throws {
        #expect(FoodKeeper.entries.count > 600)
        #expect(FoodKeeper.source.contains("FoodKeeper"))
        let potatoes = try #require(FoodKeeper.entry(id: 297))
        #expect(potatoes.name == "Potatoes")
        #expect(potatoes.unopened(.room) == .days(30...60))
        #expect(potatoes.unopened(.fridge) == .days(7...14))
        let salsa = try #require(FoodKeeper.entry(id: 357))
        #expect(salsa.unopened(.room) == .days(365...365))
        #expect(salsa.opened(.fridge) == .days(30...30))
        let milk = try #require(FoodKeeper.entry(id: 27))
        #expect(milk.unopened(.fridge) == .packageDate)
        #expect(FoodKeeper.entry(id: 6)?.freezingNotRecommended == true)
    }

    /// Grocery names as receipts, shelf scans and people write them, with
    /// the FoodKeeper entry each should get (nil: nothing fits).
    static let cases: [(String, ProductCategory, Int?)] = [
        ("Whole Milk", .dairy, 27), ("2% Milk", .dairy, 27), ("Large Eggs", .eggs, 21), ("Baby Spinach", .produce, 291),
        ("Chicken Breast", .meat, 116), ("Boneless Skinless Chicken Thighs", .meat, 118), ("Sharp Cheddar", .cheese, 3),
        ("Shredded Mozzarella", .cheese, 5), ("Greek Yogurt", .dairy, 33), ("Roma Tomatoes", .produce, 306),
        ("Russet Potatoes", .produce, 297), ("Yellow Onions", .produce, 294), ("Limes", .produce, 256),
        ("Lemons", .produce, 256), ("Bananas", .produce, 251), ("Avocados", .produce, 250), ("Strawberries", .produce, 481),
        ("Blueberries", .produce, 254), ("Jasmine Rice", .grains, 338), ("Brown Rice", .grains, 339),
        ("Spaghetti", .grains, 335), ("Penne Pasta", .grains, 335), ("Diced Tomatoes", .canned, 373),
        ("Black Beans", .canned, 372), ("Peanut Butter", .condiments, 387), ("Butter", .dairy, 1),
        ("Salted Butter", .dairy, 1), ("Ketchup", .condiments, 348), ("Mayonnaise", .condiments, 350),
        ("Yellow Mustard", .condiments, 351), ("Salsa", .condiments, 357), ("Hot Sauce", .condiments, 559),
        ("Soy Sauce", .condiments, 360), ("Orange Juice", .beverages, 455), ("Ground Beef", .meat, 43),
        ("Ground Beef 80/20", .meat, 43), ("Bacon", .meat, 79), ("Hot Dogs", .meat, 98), ("Salmon Fillet", .seafood, 146),
        ("Shrimp", .seafood, 151), ("Sliced Turkey", .deli, 514), ("Deli Ham", .deli, 515), ("Cream Cheese", .dairy, 10),
        ("Sour Cream", .dairy, 29), ("Heavy Cream", .dairy, 14), ("Half and Half", .dairy, 13),
        ("Cottage Cheese", .dairy, 9), ("Bread", .bakery, 195), ("Sourdough Bread", .bakery, 195),
        ("Whole Wheat Bread", .bakery, 461), ("Bagels", .bakery, 449), ("Tortillas", .bakery, 196),
        ("Frozen Pizza", .frozen, 571), ("Ice Cream", .frozen, 317), ("Frozen Peas", .frozen, 273),
        ("Apples", .produce, 248), ("Carrots", .produce, 279), ("Baby Carrots", .produce, 491), ("Broccoli", .produce, 276),
        ("Garlic", .produce, 285), ("Celery", .produce, 281), ("Cucumbers", .produce, 283), ("Bell Peppers", .produce, 296),
        ("Mushrooms", .produce, 292), ("Kale", .produce, 423), ("Cilantro", .produce, 506), ("Romaine Lettuce", .produce, 290),
        ("Hummus", .deli, 181), ("Guacamole", .deli, 180), ("Tofu", .other, 168), ("Olive Oil", .condiments, 227),
        ("Extra Virgin Olive Oil", .condiments, 227), ("All-Purpose Flour", .grains, 222), ("Honey", .condiments, 345),
        ("Cereal", .grains, 374), ("Crackers", .snacks, 377), ("Potato Chips", .snacks, 392),
        ("Chicken Broth", .canned, 486), ("Pickles", .condiments, 353), ("Strawberry Jam", .condiments, 347),
        ("Maple Syrup", .condiments, 533), ("Marinara Sauce", .condiments, 359), ("Tuna", .canned, 618),
        ("Canned Tuna", .canned, 618), ("Almond Milk", .dairy, 427), ("Soda", .beverages, 407),
        ("Sparkling Water", .beverages, 413), ("Red Wine", .beverages, 462), ("Pork Chops", .meat, 63),
        ("Italian Sausage", .meat, 102), ("Rotisserie Chicken", .deli, 141), ("Leftover Pizza", .leftovers, 175),
        ("Grapes", .produce, 261), ("Watermelon", .produce, 495), ("Cherry Tomatoes", .produce, 600),
        ("Green Onions", .produce, 295), ("Scallions", .produce, 295), ("Frozen Waffles", .frozen, 321),
        ("Plain Greek Yogurt", .dairy, 33), ("Whole Bean Coffee", .beverages, 400),
        ("Paper Towels", .paperGoods, nil), ("Dish Soap", .cleaning, nil), ("Laundry Detergent", .laundry, nil),
        ("Toothpaste", .personalCare, nil),
    ]

    @Test func matchesCommonGroceries() {
        var wrong: [String] = []
        for (name, category, expected) in Self.cases {
            let got = FoodKeeper.match(name: name, category: category)?.id
            if got != expected {
                wrong.append("\(name): expected \(expected.map(String.init) ?? "nil"), got \(got.map(String.init) ?? "nil") \(got.flatMap { FoodKeeper.entry(id: $0)?.displayName } ?? "")")
            }
        }
        #expect(wrong.isEmpty, "\(wrong.joined(separator: "\n"))")
    }

    @Test func brandWordsDontSteerTheMatch() {
        #expect(FoodKeeper.match(name: "Great Value Whole Milk", brand: "Great Value", category: .dairy)?.id == 27)
        #expect(FoodKeeper.match(name: "Barilla Spaghetti", brand: "Barilla", category: .grains)?.id == 335)
    }

    @Test func searchFindsEntriesByPrefix() {
        let results = FoodKeeper.search("sals")
        #expect(results.contains { $0.id == 357 })
        #expect(!results.contains { $0.id == 27 })
    }

    @Test func wordsFoldPluralsAndDropNumbers() {
        #expect(FoodKeeperMatcher.words("Tomatoes, Berries & 12 Eggs") == ["tomato", "berry", "egg"])
        #expect(FoodKeeperMatcher.singular("glass") == "glass")
        #expect(FoodKeeperMatcher.singular("peaches") == "peach")
    }
}

struct ExpiryCalculatorTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static let purchase = Date(timeIntervalSince1970: 1_790_000_000)

    func days(_ n: Int, from date: Date = purchase) -> Date {
        Self.calendar.date(byAdding: .day, value: n, to: date)!
    }

    func compute(_ inputs: ExpiryInputs, _ strictness: ExpiryStrictness = .balanced) -> ExpiryResult {
        ExpiryCalculator.compute(inputs, strictness: strictness, calendar: Self.calendar)
    }

    var potatoes: FoodKeeperEntry { FoodKeeper.entry(id: 297)! }
    var salsa: FoodKeeperEntry { FoodKeeper.entry(id: 357)! }
    var chicken: FoodKeeperEntry { FoodKeeper.entry(id: 117)! }
    var cannedLowAcid: FoodKeeperEntry { FoodKeeper.entry(id: 372)! }

    @Test func strictnessPicksThePointInUSDAsRange() {
        // Potatoes in the pantry: 1–2 months.
        let inputs = ExpiryInputs(category: .produce, foodKeeper: potatoes, climate: .room, purchaseDate: Self.purchase)
        #expect(compute(inputs, .veryCautious).date == days(30))
        #expect(compute(inputs, .balanced).date == days(45))
        #expect(compute(inputs, .veryRelaxed).date == days(60))
        #expect(compute(inputs).basis == .foodKeeper)
        #expect(compute(inputs).explanation == "USDA: 1–2 months in the pantry")
    }

    @Test func guardedFoodNeverPassesUSDAsLongestTime() {
        // Chicken in the fridge: 1–2 days, even for the most relaxed household.
        let inputs = ExpiryInputs(category: .meat, foodKeeper: chicken, climate: .fridge, purchaseDate: Self.purchase)
        #expect(compute(inputs, .veryRelaxed).date == days(2))
        // A printed date gets no extra time either.
        var printed = inputs
        printed.printedDate = days(4)
        #expect(compute(printed, .veryRelaxed).date == days(4))
        #expect(ExpiryCalculator.printedDateGrace(category: .dairy, strictness: .veryRelaxed) == 0)
        // Estimates without USDA data stop at the estimate.
        let estimated = ExpiryInputs(category: .seafood, productShelfLifeDays: 2, climate: .fridge, purchaseDate: Self.purchase)
        #expect(compute(estimated, .veryRelaxed).date == days(2))
    }

    @Test func relaxedHouseholdsKeepCannedGoodsPastTheirDate() {
        let date = days(100)
        let inputs = ExpiryInputs(category: .canned, foodKeeper: cannedLowAcid, climate: .room, purchaseDate: Self.purchase, printedDate: date)
        #expect(compute(inputs, .veryCautious).date == date)
        #expect(compute(inputs, .balanced).date == date)
        #expect(compute(inputs, .relaxed).date == days(183, from: date))
        #expect(compute(inputs, .veryRelaxed).date == days(365, from: date))
        #expect(compute(inputs, .veryRelaxed).basis == .printedDate)
    }

    @Test func openingShortensTheDate() {
        // Salsa: a year sealed in the pantry, a month in the fridge once opened.
        let opened = days(10)
        let inputs = ExpiryInputs(category: .condiments, foodKeeper: salsa, climate: .fridge, purchaseDate: Self.purchase, openedDate: opened)
        let result = compute(inputs)
        #expect(result.date == days(30, from: opened))
        #expect(result.explanation == "USDA: 1 month in the fridge once opened")
        // Opening never makes it last longer than the package date.
        var nearDate = inputs
        nearDate.printedDate = days(20)
        #expect(compute(nearDate).date == days(20))
    }

    @Test func openedCannedGoodsLeftInThePantryAreFlagged() {
        let inputs = ExpiryInputs(category: .canned, foodKeeper: cannedLowAcid, climate: .room, purchaseDate: Self.purchase, openedDate: days(5))
        #expect(compute(inputs).date == days(6))
    }

    @Test func movingCarriesOverUsedShelfLife() {
        // Balanced potatoes: 45 days in the pantry, 11 in the fridge (7–14).
        var inputs = ExpiryInputs(category: .produce, foodKeeper: potatoes, climate: .room, purchaseDate: Self.purchase)
        let moved = days(15)
        let used = ExpiryCalculator.shelfLifeUsed(inputs, at: moved, strictness: .balanced)
        #expect(abs(used - 1.0 / 3.0) < 0.001)
        inputs.climate = .fridge
        inputs.climateSince = moved
        inputs.shelfLifeUsed = used
        // Two thirds of the fridge time left.
        #expect(compute(inputs).date == days(7, from: moved))
    }

    @Test func freezingRestartsTheClockAndThawingUsesThawTimes() {
        let frozen = days(1)
        var inputs = ExpiryInputs(category: .meat, foodKeeper: chicken, climate: .freezer, purchaseDate: Self.purchase, climateSince: frozen)
        // Chicken parts: 9 months frozen.
        #expect(compute(inputs).date == days(270, from: frozen))
        // Thawed with no USDA thawing time: fridge time after opening, else a few days.
        let thawed = days(40)
        inputs.climate = .fridge
        inputs.climateSince = thawed
        inputs.thawedDate = thawed
        let result = compute(inputs, .veryRelaxed)
        #expect(result.date! <= days(3, from: thawed))
    }

    @Test func fallsBackToEstimatesThenTheCategoryTable() {
        let estimate = ExpiryInputs(category: .snacks, productShelfLifeDays: 40, climate: .room, purchaseDate: Self.purchase)
        #expect(compute(estimate, .veryCautious).date == days(30))
        #expect(compute(estimate, .veryRelaxed).date == days(50))
        #expect(compute(estimate).basis == .productEstimate)
        let table = ExpiryInputs(category: .snacks, climate: .room, purchaseDate: Self.purchase)
        #expect(compute(table).basis == .categoryDefault)
        #expect(compute(table).date == days(90))
        let household = ExpiryInputs(category: .cleaning, climate: .room, purchaseDate: Self.purchase)
        #expect(compute(household).date == nil)
    }

    @Test func milkFollowsItsPackageDate() {
        // FoodKeeper only says "package date" for milk; without one, the table.
        let milk = FoodKeeper.entry(id: 27)!
        let inputs = ExpiryInputs(category: .dairy, foodKeeper: milk, climate: .fridge, purchaseDate: Self.purchase)
        #expect(compute(inputs).basis == .categoryDefault)
        var dated = inputs
        dated.printedDate = days(12)
        #expect(compute(dated, .veryRelaxed).date == days(12))
    }

    @Test func describesRanges() {
        #expect(ExpiryCalculator.describe(1...2) == "1–2 days")
        #expect(ExpiryCalculator.describe(7...14) == "1–2 weeks")
        #expect(ExpiryCalculator.describe(30...60) == "1–2 months")
        #expect(ExpiryCalculator.describe(365...548) == "12–18 months")
        #expect(ExpiryCalculator.describe(730...1825) == "2–5 years")
        #expect(ExpiryCalculator.describe(7...7) == "7 days")
    }
}

struct PrintedDateParserTests {
    static var calendar: Calendar { ExpiryCalculatorTests.calendar }
    /// 2026-09-27
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func parse(_ text: String, dayFirst: Bool = false) -> PrintedDate? {
        PrintedDateParser.parse(text, now: Self.now, dayFirst: dayFirst, calendar: Self.calendar)
    }

    @Test func readsCommonFormats() {
        #expect(parse("BEST BY 12/15/26")?.date == date(2026, 12, 15))
        #expect(parse("BEST BY 12/15/26")?.kind == .bestBy)
        #expect(parse("EXP 2027-03-01")?.date == date(2027, 3, 1))
        #expect(parse("EXP 2027-03-01")?.kind == .useBy)
        #expect(parse("USE BY 15 DEC 2026")?.date == date(2026, 12, 15))
        #expect(parse("Best Before: Dec 15, 2026")?.date == date(2026, 12, 15))
        #expect(parse("BB 15.12.26")?.date == date(2026, 12, 15))
        #expect(parse("15DEC26")?.date == date(2026, 12, 15))
        #expect(parse("EXP 06/2028")?.date == date(2028, 6, 30))
        #expect(parse("MAR 2027")?.date == date(2027, 3, 31))
    }

    @Test func shortDatesMeanTheNextOccurrence() {
        let sellBy = parse("SELL BY OCT 03")
        #expect(sellBy?.date == date(2026, 10, 3))
        #expect(sellBy?.kind == .sellBy)
        #expect(parse("BEST BY 12/15")?.date == date(2026, 12, 15))
    }

    @Test func ignoresLotCodesAndTimes() {
        let result = parse("BEST IF USED BY JAN 05 2027 L2345 14:32")
        #expect(result?.date == date(2027, 1, 5))
        #expect(parse("LOT 4471 PLANT 22") == nil)
        #expect(parse("Nutrition Facts 2000 calories") == nil)
    }

    @Test func prefersTheLabeledDate() {
        // A packing date and a best-by date on the same label.
        let result = parse("PACKED 09/01/26 BEST BY 03/01/27")
        #expect(result?.date == date(2027, 3, 1))
        #expect(result?.kind == .bestBy)
    }

    @Test func dayFirstRegions() {
        #expect(parse("05/06/27")?.date == date(2027, 5, 6))
        #expect(parse("05/06/27", dayFirst: true)?.date == date(2027, 6, 5))
        // A day over 12 settles it either way.
        #expect(parse("25/06/27")?.date == date(2027, 6, 25))
    }

    @Test func dropsImplausibleDates() {
        #expect(parse("EXP 01/01/19") == nil)
        #expect(parse("EXP 01/01/2099") == nil)
    }
}
