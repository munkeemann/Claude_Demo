import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Looks barcodes up in Open Food Facts, then Open Beauty Facts, then Open
/// Products Facts. All three share the same v2 product API.
///
/// Open Food Facts asks clients to send a descriptive User-Agent and keep
/// product reads under ~100 requests/minute; one household never gets close.
public struct OpenFactsClient: ProductLookupService {
    static let fields = [
        "code", "product_name", "product_name_en", "generic_name", "brands",
        "quantity", "categories_tags", "image_front_small_url", "image_url",
    ].joined(separator: ",")

    private let http: any HTTPClient
    private let userAgent: String
    private let databases: [OpenFactsDatabase]

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        userAgent: String,
        databases: [OpenFactsDatabase] = OpenFactsDatabase.allCases
    ) {
        self.http = http
        self.userAgent = userAgent
        self.databases = databases
    }

    public func lookup(barcode: String) async throws -> ProductLookupResult? {
        let code = TextNormalizer.barcode(barcode)
        guard (8...14).contains(code.count) else { throw ProductLookupError.invalidBarcode }
        for database in databases {
            if let result = try await lookup(code: code, in: database) {
                return result
            }
        }
        return nil
    }

    func request(code: String, database: OpenFactsDatabase) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = database.host
        components.path = "/api/v2/product/\(code)"
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func lookup(code: String, in database: OpenFactsDatabase) async throws -> ProductLookupResult? {
        let (data, response) = try await http.send(request(code: code, database: database))
        switch response.statusCode {
        case 200:
            break
        case 404:
            // v2 answers 404 (with a JSON body) for unknown barcodes.
            return nil
        case 429:
            throw ProductLookupError.rateLimited
        default:
            throw ProductLookupError.httpStatus(response.statusCode)
        }
        let payload = try JSONDecoder().decode(OpenFactsResponse.self, from: data)
        guard let product = payload.product else { return nil }
        return OpenFactsMapper.map(product, barcode: code, source: database)
    }
}

// MARK: - DTOs

struct OpenFactsResponse: Decodable {
    let product: OpenFactsProduct?
}

struct OpenFactsProduct: Decodable {
    let productName: String?
    let productNameEn: String?
    let genericName: String?
    let brands: String?
    let quantity: String?
    let categoriesTags: [String]?
    let imageFrontSmallURL: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case productNameEn = "product_name_en"
        case genericName = "generic_name"
        case brands
        case quantity
        case categoriesTags = "categories_tags"
        case imageFrontSmallURL = "image_front_small_url"
        case imageURL = "image_url"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Open*Facts data is crowd-sourced; tolerate wrong types field by field.
        productName = try? container.decodeIfPresent(String.self, forKey: .productName)
        productNameEn = try? container.decodeIfPresent(String.self, forKey: .productNameEn)
        genericName = try? container.decodeIfPresent(String.self, forKey: .genericName)
        brands = try? container.decodeIfPresent(String.self, forKey: .brands)
        quantity = try? container.decodeIfPresent(String.self, forKey: .quantity)
        categoriesTags = try? container.decodeIfPresent([String].self, forKey: .categoriesTags)
        imageFrontSmallURL = try? container.decodeIfPresent(String.self, forKey: .imageFrontSmallURL)
        imageURL = try? container.decodeIfPresent(String.self, forKey: .imageURL)
    }
}

// MARK: - Mapping

enum OpenFactsMapper {
    static func map(_ product: OpenFactsProduct, barcode: String, source: OpenFactsDatabase) -> ProductLookupResult? {
        guard let name = firstNonEmpty(product.productNameEn, product.productName, product.genericName) else {
            return nil
        }
        let brand = product.brands?
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let sizeText = firstNonEmpty(product.quantity)
        let imageURL = firstNonEmpty(product.imageFrontSmallURL, product.imageURL).flatMap(URL.init(string:))
        let category = OpenFactsCategoryMapper.category(
            tags: product.categoriesTags ?? [],
            name: name,
            source: source
        )
        return ProductLookupResult(
            barcode: barcode,
            name: name,
            brand: brand,
            category: category,
            packageSize: sizeText.flatMap(PackageSize.parse),
            packageSizeText: sizeText,
            imageURL: imageURL,
            source: source
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
