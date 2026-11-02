import Foundation

public enum Barcode {
    /// One key for UPC-A / EAN-13 / zero-padded GTIN-14 representations.
    public static func normalized(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [8, 12, 13, 14].contains(code.count),
              code.utf8.allSatisfy({ (48...57).contains($0) }),
              validCheckDigit(code) else { return nil }
        if code.count == 12 { return "0" + code }
        if code.count == 14, code.first == "0" { return String(code.dropFirst()) }
        return code
    }

    /// AVFoundation reports UPC-E separately from EAN-8. Expand it before lookup.
    public static func expandedUPCE(_ code: String) -> String? {
        guard code.count == 8, code.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let d = Array(code).map(String.init)
        guard d[0] == "0" || d[0] == "1" else { return nil }
        let body: String
        switch d[6] {
        case "0", "1", "2": body = d[0] + d[1] + d[2] + d[6] + "0000" + d[3] + d[4] + d[5]
        case "3": body = d[0] + d[1] + d[2] + d[3] + "00000" + d[4] + d[5]
        case "4": body = d[0] + d[1] + d[2] + d[3] + d[4] + "00000" + d[5]
        default: body = d[0] + d[1] + d[2] + d[3] + d[4] + d[5] + "0000" + d[6]
        }
        return normalized(body + d[7])
    }

    private static func validCheckDigit(_ code: String) -> Bool {
        let digits = code.utf8.map { Int($0 - 48) }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10 == digits.last
    }
}

public enum ProductLookupError: LocalizedError {
    case invalidBarcode, notFound, incomplete, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidBarcode: return "Dieser Barcode ist ungültig. Gib die 8, 12, 13 oder 14 Ziffern unter dem Produktbarcode ein."
        case .notFound: return "Dieses Produkt ist noch nicht in Open Food Facts. Du kannst es einmal selbst hinterlegen."
        case .incomplete: return "Für dieses Produkt fehlen vollständige Nährwerte. Übernimm sie einmal von der Verpackung."
        case .unavailable: return "Die Produktdatenbank ist gerade nicht erreichbar. Versuche es später oder erfasse das Produkt von Hand."
        }
    }
}

public enum ProductDecoder {
    public static func decode(_ data: Data, barcode: String) throws -> ProductRecord {
        guard data.count < 1_000_000,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ProductLookupError.incomplete }
        if (root["status"] as? Int) == 0 { throw ProductLookupError.notFound }
        guard let product = root["product"] as? [String: Any],
              let nutrients = product["nutriments"] as? [String: Any] else { throw ProductLookupError.incomplete }
        func number(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        func text(_ key: String) -> String? {
            (product[key] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let calories = number(nutrients["energy-kcal_100g"]) ?? number(nutrients["energy-kj_100g"]).map { $0 / 4.184 } ?? number(nutrients["energy_100g"]).map { $0 / 4.184 }
        guard let calories, let protein = number(nutrients["proteins_100g"]),
              let carbs = number(nutrients["carbohydrates_100g"]), let fat = number(nutrients["fat_100g"]),
              let name = text("product_name_de") ?? text("product_name") ?? text("generic_name_de") ?? text("generic_name") else { throw ProductLookupError.incomplete }
        let nutrition = Nutrition(calories: calories, protein: protein, carbs: carbs, fat: fat)
        guard nutrition.isValid, calories <= 1000, protein <= 100, carbs <= 100, fat <= 100 else { throw ProductLookupError.incomplete }
        return ProductRecord(barcode: barcode, name: String(name.prefix(200)),
            categories: (product["categories_tags"] as? [String] ?? []).joined(separator: " "),
            quantityText: text("quantity") ?? "", quantity: number(product["product_quantity"]),
            quantityUnit: text("product_quantity_unit") ?? "g", serving: text("serving_size") ?? "", per100: nutrition)
    }
}
