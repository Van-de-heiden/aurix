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
        guard (8...14).contains(code.count), code.allSatisfy(\.isNumber) else { throw CoreError.incompleteProduct }
        load()
        if let hit = cache[code] { return hit.product }
        let fields = "product_name,product_name_de,brands,categories_tags,quantity,product_quantity,product_quantity_unit,serving_size,nutriments"
        var request = URLRequest(url: URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)")!)
        request.setValue("AURIX-Personal/1.0 (iOS; https://github.com/Van-de-heiden/aurix)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 1_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = root["product"] as? [String: Any], let nutrients = product["nutriments"] as? [String: Any] else { throw CoreError.incompleteProduct }
        func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        let calories = number(nutrients["energy-kcal_100g"]) ?? number(nutrients["energy-kj_100g"]).map { $0 / 4.184 } ?? number(nutrients["energy_100g"]).map { $0 / 4.184 }
        guard let calories, let protein = number(nutrients["proteins_100g"]), let carbs = number(nutrients["carbohydrates_100g"]), let fat = number(nutrients["fat_100g"]),
              let name = (product["product_name_de"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? (product["product_name"] as? String), !name.isEmpty else { throw CoreError.incompleteProduct }
        let result = ProductRecord(barcode: code, name: String(name.prefix(200)),
            categories: (product["categories_tags"] as? [String] ?? []).joined(separator: " "),
            quantityText: product["quantity"] as? String ?? "", quantity: number(product["product_quantity"]),
            quantityUnit: product["product_quantity_unit"] as? String ?? "g", serving: product["serving_size"] as? String ?? "",
            per100: Nutrition(calories: calories, protein: protein, carbs: carbs, fat: fat))
        guard result.per100.isValid, calories <= 1000, protein <= 100, carbs <= 100, fat <= 100 else { throw CoreError.incompleteProduct }
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
