import Testing
@testable import InventoryCore

struct MeasureUnitTests {
    @Test func convertsWithinMass() throws {
        let grams = try #require(MeasureUnit.pound.convert(1, to: .gram))
        #expect(abs(grams - 453.59237) < 0.0001)
        let pounds = try #require(MeasureUnit.ounce.convert(16, to: .pound))
        #expect(abs(pounds - 1) < 0.0001)
    }

    @Test func convertsWithinVolume() throws {
        let quarts = try #require(MeasureUnit.gallon.convert(1, to: .quart))
        #expect(abs(quarts - 4) < 0.0001)
        let cups = try #require(MeasureUnit.liter.convert(1, to: .cup))
        #expect(abs(cups - 4.22675) < 0.001)
    }

    @Test func convertsDozenToEach() {
        #expect(MeasureUnit.dozen.convert(1.5, to: .each) == 18)
    }

    @Test func refusesCrossDimensionConversion() {
        #expect(MeasureUnit.gallon.convert(1, to: .pound) == nil)
        #expect(MeasureUnit.each.convert(1, to: .gram) == nil)
    }

    @Test func containersOnlyConvertToThemselves() {
        #expect(MeasureUnit.can.convert(3, to: .can) == 3)
        #expect(MeasureUnit.can.convert(3, to: .jar) == nil)
        #expect(MeasureUnit.pack.convert(1, to: .each) == nil)
    }

    @Test(arguments: [
        (1.0, MeasureUnit.can, "1 can"),
        (2.0, .can, "2 cans"),
        (2.0, .box, "2 boxes"),
        (1.5, .pound, "1.5 lb"),
        (3.0, .each, "3"),
        (0.333333, .gallon, "0.33 gal"),
        (2.0, .fluidOunce, "2 fl oz"),
    ])
    func labels(value: Double, unit: MeasureUnit, expected: String) {
        #expect(unit.label(for: value) == expected)
    }

    @Test func rawValuesAreUnique() {
        let raws = MeasureUnit.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test func quantityConversion() throws {
        let quantity = Quantity(2, .kilogram)
        let pounds = try #require(quantity.converted(to: .pound))
        #expect(abs(pounds.value - 4.40924) < 0.0001)
        #expect(pounds.unit == .pound)
    }
}
