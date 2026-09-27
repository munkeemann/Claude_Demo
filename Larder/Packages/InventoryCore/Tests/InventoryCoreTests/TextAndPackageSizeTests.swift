import Testing
@testable import InventoryCore

struct TextNormalizerTests {
    @Test(arguments: [
        ("  Great-Value WHOLE Milk, 1 GAL ", "great value whole milk 1 gal"),
        ("Crème Fraîche", "creme fraiche"),
        ("GV WHL MLK 1.5G", "gv whl mlk 1.5g"),
        ("Bush's Black Beans", "bush s black beans"),
        ("Tide... Pods!!", "tide pods"),
        ("50% less sodium", "50% less sodium"),
    ])
    func key(input: String, expected: String) {
        #expect(TextNormalizer.key(input) == expected)
    }

    @Test func barcodeWidensUPCAToEAN13() {
        #expect(TextNormalizer.barcode("0 76808 28059 3") == "0076808280593")
        #expect(TextNormalizer.barcode("3017624010701") == "3017624010701")
        #expect(TextNormalizer.barcode("96385074") == "96385074")
    }
}

struct PackageSizeTests {
    @Test func parsesSimpleSizes() {
        #expect(PackageSize.parse("1 gal") == PackageSize(count: 1, unitSize: Quantity(1, .gallon)))
        #expect(PackageSize.parse("500 g") == PackageSize(count: 1, unitSize: Quantity(500, .gram)))
        #expect(PackageSize.parse("1.5L") == PackageSize(count: 1, unitSize: Quantity(1.5, .liter)))
        #expect(PackageSize.parse("16.9 fl oz") == PackageSize(count: 1, unitSize: Quantity(16.9, .fluidOunce)))
        #expect(PackageSize.parse("16 fl. oz.") == PackageSize(count: 1, unitSize: Quantity(16, .fluidOunce)))
        #expect(PackageSize.parse("2 LBS") == PackageSize(count: 1, unitSize: Quantity(2, .pound)))
    }

    @Test func parsesEuropeanDecimalComma() {
        #expect(PackageSize.parse("0,75 l") == PackageSize(count: 1, unitSize: Quantity(0.75, .liter)))
    }

    @Test func parsesMultipacks() {
        #expect(PackageSize.parse("6 x 330 ml") == PackageSize(count: 6, unitSize: Quantity(330, .milliliter)))
        #expect(PackageSize.parse("12 × 12 fl oz") == PackageSize(count: 12, unitSize: Quantity(12, .fluidOunce)))
    }

    @Test func countsBecomeCounts() {
        #expect(PackageSize.parse("12 rolls") == PackageSize(count: 12, unitSize: nil))
        #expect(PackageSize.parse("24 ct") == PackageSize(count: 24, unitSize: nil))
        #expect(PackageSize.parse("1 dozen") == PackageSize(count: 12, unitSize: nil))
    }

    @Test func findsSizeInsideLongerText() {
        #expect(PackageSize.parse("Net wt 15 oz (425g)") == PackageSize(count: 1, unitSize: Quantity(15, .ounce)))
    }

    @Test func rejectsUnparseableText() {
        #expect(PackageSize.parse("") == nil)
        #expect(PackageSize.parse("family size") == nil)
        #expect(PackageSize.parse("42") == nil)
    }

    @Test func labels() {
        #expect(PackageSize(count: 6, unitSize: Quantity(330, .milliliter)).label == "6 × 330 ml")
        #expect(PackageSize(count: 12, unitSize: nil).label == "12 ct")
        #expect(PackageSize(count: 1, unitSize: Quantity(1, .gallon)).label == "1 gal")
    }
}
