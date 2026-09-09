import Foundation
import AurixCore

@MainActor
enum AIService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    static var requestsToday: Int {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "aiUsageDay") == dayKey ? defaults.integer(forKey: "aiUsageCount") : 0
    }
    private static var dayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    static func estimate(text: String, image: Data? = nil) async throws -> MealEstimate {
        guard UserDefaults.standard.bool(forKey: "aiConsent") else { throw ServiceError.consent }
        guard let key = Keychain.read() else { throw ServiceError.keyMissing }
        let configured = UserDefaults.standard.integer(forKey: "aiDailyLimit")
        let limit = configured > 0 ? min(50, max(5, configured)) : 20
        guard requestsToday < limit else { throw ServiceError.limit }
        let body = try AIContract.body(text: text, imageData: image)
        guard body.count <= 4_000_000 else { throw ServiceError.imageTooLarge }
        try Task.checkCancellation()
        // Reserve before the request, including failures. No automatic retries or duplicate submissions.
        let used = requestsToday
        UserDefaults.standard.set(dayKey, forKey: "aiUsageDay")
        UserDefaults.standard.set(used + 1, forKey: "aiUsageCount")
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ServiceError.unavailable }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw ServiceError.keyRejected
        case 429: throw ServiceError.apiLimit
        default: throw ServiceError.unavailable
        }
        guard data.count <= 500_000 else { throw CoreError.invalidNutrition }
        return try AIContract.parse(data)
    }
    enum ServiceError: LocalizedError {
        case consent, keyMissing, keyRejected, limit, apiLimit, unavailable, imageTooLarge
        var errorDescription: String? {
            switch self {
            case .consent: return "Aktiviere die KI-Erfassung einmal in den Einstellungen."
            case .keyMissing: return "Hinterlege deinen OpenAI-Schlüssel einmal unter Einstellungen → KI verbinden."
            case .keyRejected: return "OpenAI hat den Schlüssel abgelehnt. Prüfe ihn und den Modellzugriff in deinen KI-Einstellungen."
            case .limit: return "Dein Tageslimit für KI-Erfassungen ist erreicht. Barcode und manuelle Einträge funktionieren weiter."
            case .apiLimit: return "OpenAI meldet ein Anfrage- oder Guthabenlimit. Versuche es später erneut oder prüfe dein API-Guthaben."
            case .unavailable: return "Die KI ist gerade nicht erreichbar. Es wurde nichts eingetragen. Bitte versuche es nochmals."
            case .imageTooLarge: return "Dieses Foto ist zu gross. Bitte nimm es erneut auf."
            }
        }
    }
}
