import Foundation
import Testing
@testable import InventoryCore

/// Response bodies modeled on real Open*Facts v2 responses.
enum OpenFactsFixtures {
    static let spaghetti = """
    {
      "code": "0076808280593",
      "product": {
        "brands": "Barilla, Barilla America",
        "categories_tags": ["en:plant-based-foods-and-beverages", "en:plant-based-foods",
                            "en:cereals-and-potatoes", "en:cereals-and-their-products", "en:pastas",
                            "en:spaghetti"],
        "image_front_small_url": "https://images.openfoodfacts.org/images/products/007/680/828/0593/front_en.3.200.jpg",
        "product_name": "Spaghetti",
        "quantity": "16 oz"
      },
      "status": 1,
      "status_verbose": "product found"
    }
    """

    static let wholeMilk = """
    {
      "code": "0078742371937",
      "product": {
        "brands": "Great Value",
        "categories_tags": ["en:dairies", "en:milks", "en:whole-milks"],
        "product_name": "",
        "product_name_en": "Whole Milk",
        "quantity": "1 gal (3.78 L)"
      },
      "status": 1
    }
    """

    static let orangeJuice = """
    {"code":"0048500202791","product":{"product_name":"Pure Premium Orange Juice","brands":"Tropicana",
     "categories_tags":["en:plant-based-foods-and-beverages","en:beverages","en:plant-based-beverages",
     "en:fruit-based-beverages","en:juices-and-nectars","en:fruit-juices","en:orange-juices"],
     "quantity":"52 fl oz"},"status":1}
    """

    static let frozenPizza = """
    {"code":"0071921003394","product":{"product_name":"Pepperoni Pizza","brands":"DiGiorno",
     "categories_tags":["en:meals","en:pizzas-pies-and-quiches","en:pizzas","en:frozen-foods","en:frozen-pizzas"],
     "quantity":"27.5 oz"},"status":1}
    """

    static let notFound = """
    {"code":"0000000000000","status":0,"status_verbose":"product not found"}
    """

    static let dishSoap = """
    {"code":"0037000973417","product":{"product_name":"Dawn Ultra Dish Soap Original Scent","brands":"Dawn",
     "categories_tags":[],"quantity":"19.4 fl oz"},"status":1}
    """

    static let shampoo = """
    {"code":"3600541234567","product":{"product_name":"Everpure Shampoo","brands":"L'Oréal",
     "categories_tags":["en:hair-care"],"quantity":"250 ml"},"status":1}
    """

    static let messyTypes = """
    {"code":"123456789012","product":{"product_name":"Mystery Crackers","brands":42,
     "categories_tags":"en:snacks","quantity":null},"status":1}
    """
}

struct OpenFactsClientTests {
    typealias Fixtures = OpenFactsFixtures

    func client(_ responses: [String: StubHTTPClient.Response]) -> (OpenFactsClient, StubHTTPClient) {
        let stub = StubHTTPClient(responses)
        return (OpenFactsClient(http: stub, userAgent: "LarderTests/1.0"), stub)
    }

    @Test func mapsFoodProduct() async throws {
        let (client, stub) = client(["world.openfoodfacts.org": .init(status: 200, body: Fixtures.spaghetti)])
        let result = try #require(try await client.lookup(barcode: "076808280593"))
        #expect(result.name == "Spaghetti")
        #expect(result.brand == "Barilla")
        #expect(result.category == .grains)
        #expect(result.packageSize == PackageSize(count: 1, unitSize: Quantity(16, .ounce)))
        #expect(result.packageSizeText == "16 oz")
        #expect(result.imageURL?.host == "images.openfoodfacts.org")
        #expect(result.source == .food)
        #expect(result.barcode == "0076808280593")
        #expect(stub.requestedHosts == ["world.openfoodfacts.org"])
    }

    @Test func sendsUserAgentAndFieldList() async throws {
        let (client, stub) = client(["world.openfoodfacts.org": .init(status: 200, body: Fixtures.spaghetti)])
        _ = try await client.lookup(barcode: "0076808280593")
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "LarderTests/1.0")
        #expect(request.url?.path == "/api/v2/product/0076808280593")
        #expect(request.url?.query?.contains("categories_tags") == true)
    }

    @Test func prefersEnglishNameWhenGenericNameIsBlank() async throws {
        let (client, _) = client(["world.openfoodfacts.org": .init(status: 200, body: Fixtures.wholeMilk)])
        let result = try #require(try await client.lookup(barcode: "0078742371937"))
        #expect(result.name == "Whole Milk")
        #expect(result.category == .dairy)
        #expect(result.packageSize?.unitSize == Quantity(1, .gallon))
    }

    @Test func fallsThroughToOtherDatabases() async throws {
        let (client, stub) = client([
            "world.openfoodfacts.org": .init(status: 404, body: Fixtures.notFound),
            "world.openbeautyfacts.org": .init(status: 200, body: Fixtures.shampoo),
        ])
        let result = try #require(try await client.lookup(barcode: "3600541234567"))
        #expect(result.source == .beauty)
        #expect(result.category == .personalCare)
        #expect(stub.requestedHosts == ["world.openfoodfacts.org", "world.openbeautyfacts.org"])
    }

    @Test func returnsNilWhenNoDatabaseKnowsTheBarcode() async throws {
        let (client, stub) = client([:])
        let result = try await client.lookup(barcode: "0000000000000")
        #expect(result == nil)
        #expect(stub.requestedHosts.count == 3)
    }

    @Test func treatsStatusZeroWithoutProductAsNotFound() async throws {
        let (client, _) = client(["world.openfoodfacts.org": .init(status: 200, body: Fixtures.notFound)])
        #expect(try await client.lookup(barcode: "0000000000000") == nil)
    }

    @Test func rejectsInvalidBarcodes() async {
        let (client, _) = client([:])
        await #expect(throws: ProductLookupError.invalidBarcode) {
            try await client.lookup(barcode: "12-34")
        }
    }

    @Test func surfacesRateLimiting() async {
        let (client, _) = client(["world.openfoodfacts.org": .init(status: 429, body: "")])
        await #expect(throws: ProductLookupError.rateLimited) {
            try await client.lookup(barcode: "0076808280593")
        }
    }

    @Test func toleratesWrongFieldTypes() async throws {
        let (client, _) = client(["world.openfoodfacts.org": .init(status: 200, body: Fixtures.messyTypes)])
        let result = try #require(try await client.lookup(barcode: "123456789012"))
        #expect(result.name == "Mystery Crackers")
        #expect(result.brand == nil)
        #expect(result.packageSize == nil)
    }
}

struct OpenFactsCategoryMapperTests {
    func category(_ json: String, source: OpenFactsDatabase = .food) throws -> ProductCategory {
        let response = try JSONDecoder().decode(OpenFactsResponse.self, from: Data(json.utf8))
        let product = try #require(response.product)
        return try #require(OpenFactsMapper.map(product, barcode: "1", source: source)).category
    }

    @Test func plantBasedTagDoesNotMakeEverythingABeverage() throws {
        #expect(try category(OpenFactsFixtures.spaghetti) == .grains)
    }

    @Test func juiceIsABeverage() throws {
        #expect(try category(OpenFactsFixtures.orangeJuice) == .beverages)
    }

    @Test func frozenBeatsOtherTags() throws {
        #expect(try category(OpenFactsFixtures.frozenPizza) == .frozen)
    }

    @Test func householdGoodsMatchByName() throws {
        #expect(try category(OpenFactsFixtures.dishSoap, source: .products) == .cleaning)
    }

    @Test(arguments: [
        (["en:dairies", "en:cheeses", "en:cheddar"], ProductCategory.cheese),
        (["en:dairies", "en:butters"], .dairy),
        (["en:plant-based-foods-and-beverages", "en:beverages", "en:plant-based-milks"], .dairy),
        (["en:canned-foods", "en:fishes", "en:canned-fishes", "en:tunas"], .canned),
        (["en:meats", "en:prepared-meats", "en:hams"], .deli),
        (["en:plant-based-foods", "en:fruits", "en:fresh-fruits", "en:bananas"], .produce),
        (["en:snacks", "en:sweet-snacks", "en:biscuits"], .snacks),
        (["en:cereals-and-their-products", "en:breads", "en:sliced-breads"], .bakery),
        (["fr:laits-demi-ecremes", "en:milks"], .dairy),
        ([], .other),
    ])
    func tagRules(tags: [String], expected: ProductCategory) {
        #expect(OpenFactsCategoryMapper.category(tags: tags, name: "x", source: .food) == expected)
    }

    @Test(arguments: [
        ("Tide Original Laundry Detergent", ProductCategory.laundry),
        ("Charmin Ultra Soft Toilet Paper", .paperGoods),
        ("Pampers Baby Wipes", .baby),
        ("Clorox Disinfecting Wipes", .cleaning),
        ("Colgate Toothpaste", .personalCare),
        ("Purina Dog Food", .pet),
    ])
    func nameRules(name: String, expected: ProductCategory) {
        #expect(OpenFactsCategoryMapper.category(tags: [], name: name, source: .products) == expected)
    }
}
