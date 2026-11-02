import Foundation
import AurixCore

actor BarcodeService {
    static let shared = BarcodeService()
    private struct Cached: Codable { var product: ProductRecord; var storedAt: Date }
    private var cache: [String: Cached] = [:]
    private var loaded = false
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil; c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 20
        return URLSession(configuration: c)
    }()
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("aurix-products.json")
    }
    func product(for code: String) async throws -> ProductRecord {
        guard let code = Barcode.normalized(code) else { throw ProductLookupError.invalidBarcode }
        load()
        if let hit = cache[code], hit.storedAt > Date().addingTimeInterval(-30 * 86400) { return hit.product }
        cache[code] = nil
        let fields = "product_name,product_name_de,generic_name,generic_name_de,categories_tags,quantity,product_quantity,product_quantity_unit,serving_size,nutriments"
        var request = URLRequest(url: URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)")!)
        request.setValue("DAYFUEL/2.0 (iOS; https://github.com/Van-de-heiden/aurix)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw ProductLookupError.unavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ProductLookupError.unavailable }
        if http.statusCode == 404 { throw ProductLookupError.notFound }
        guard http.statusCode == 200 else { throw ProductLookupError.unavailable }
        let result = try ProductDecoder.decode(data, barcode: code)
        cache[code] = Cached(product: result, storedAt: Date())
        trim(); persist()
        return result
    }
    func clear() { cache = [:]; loaded = true; try? FileManager.default.removeItem(at: cacheURL) }
    func maintenance() { load(); trim(); persist() }
    private func load() {
        guard !loaded else { return }; loaded = true
        if let data = try? Data(contentsOf: cacheURL), data.count < 2_000_000,
           let decoded = try? JSONDecoder().decode([String: Cached].self, from: data) { cache = decoded }
        trim()
    }
    private func trim() {
        let earliest = Date().addingTimeInterval(-30 * 86400)
        cache = cache.filter { $0.value.storedAt > earliest }
        if cache.count > 200 { cache = Dictionary(uniqueKeysWithValues: cache.sorted { $0.value.storedAt > $1.value.storedAt }.prefix(200).map { ($0.key, $0.value) }) }
    }
    private func persist() { if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) } }
}
