import Foundation

public struct ProductRecord: Codable, Sendable {
    public var barcode: String
    public var name: String
    public var categories: String
    public var quantityText: String
    public var quantity: Double?
    public var quantityUnit: String
    public var serving: String
    public var per100: Nutrition
    public init(barcode: String, name: String, categories: String = "", quantityText: String = "", quantity: Double? = nil,
                quantityUnit: String = "g", serving: String = "", per100: Nutrition) {
        self.barcode = barcode; self.name = name; self.categories = categories; self.quantityText = quantityText
        self.quantity = quantity; self.quantityUnit = quantityUnit; self.serving = serving; self.per100 = per100
    }
}

public struct ResolvedPortion: Sendable {
    public var amount: Double
    public var unit: String
    public var label: String
    public var assumed: Bool
    public var nutrition: Nutrition
}

public enum ProductResolver {
    public static func measurement(in text: String) -> (amount: Double, unit: String)? {
        let pattern = #"(?i)(\d+(?:[.,]\d+)?)\s*(kg|ml|cl|g|l)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
              let number = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")), number > 0 else { return nil }
        switch text[unitRange].lowercased() {
        case "kg": return (number * 1000, "g")
        case "l": return (number * 1000, "ml")
        case "cl": return (number * 10, "ml")
        case "ml": return (number, "ml")
        default: return (number, "g")
        }
    }

    public static func resolve(_ product: ProductRecord) throws -> ResolvedPortion {
        guard product.per100.isValid else { throw CoreError.incompleteProduct }
        let parsedPackage = measurement(in: product.quantityText)
        let packageUnit = parsedPackage?.unit ?? (product.quantityUnit == "ml" ? "ml" : "g")
        // OFF product_quantity is the normalized package amount; never multiply this by package count again.
        let package = product.quantity.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } ?? parsedPackage?.amount
        let serving = measurement(in: product.serving)
        let text = (product.categories + " " + product.name).lowercased()
        let multi = product.quantityText.range(of: #"\d+\s*[x×]\s*\d"#, options: .regularExpression) != nil
        let single = text.range(of: #"\b(sandwich(?:es)?|wraps?|bars?|proteinriegel|riegel|yogurts?|yoghurts?|joghurts?|skyr|drinks?|proteindrink|beverages?|getränke?|ready-meals?|prepared-meals?)\b"#, options: .regularExpression) != nil
        let singleLimit: Double = (packageUnit == "ml" || text.contains("sandwich") || text.contains("ready-meal") || text.contains("prepared-meal")) ? 600 : 250
        let amount: Double; let unit: String; let label: String; let assumed: Bool
        if single, !multi, let package, package <= singleLimit {
            amount = package; unit = packageUnit; label = "1 ganze Einheit · \(format(package)) \(unit)"; assumed = false
        } else if let serving {
            amount = serving.amount; unit = serving.unit; label = "1 Portion · \(format(amount)) \(unit)"; assumed = false
        } else if multi, let item = parsedPackage {
            amount = item.amount; unit = item.unit; label = "1 Stück · \(format(amount)) \(unit)"; assumed = false
        } else {
            amount = 100; unit = packageUnit; label = "100 \(unit) · Standardmenge"; assumed = true
        }
        let nutrition = product.per100.scaled(by: amount / 100)
        guard nutrition.isValid, amount <= 5_000 else { throw CoreError.incompleteProduct }
        return ResolvedPortion(amount: amount, unit: unit, label: label, assumed: assumed, nutrition: nutrition)
    }

    private static func format(_ number: Double) -> String { number == number.rounded() ? String(Int(number)) : String(number) }
}
