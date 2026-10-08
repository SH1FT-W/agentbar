import SwiftUI

/// Wetter hinter der Glasfront – vereinfacht auf das, was die Szene zeichnen kann.
struct Weather: Equatable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case clear, partly, cloudy, fog, drizzle, rain, thunder, snow
    }
    var kind: Kind
    /// 0…1: wie stark es regnet/schneit (Niesel ≈ 0.3, Starkregen 1)
    var intensity: Double
    /// Wolkendecke 0…1
    var cloudCover: Double
    var temperature: Double
    /// km/h
    var wind: Double
    /// Schneedecke am Boden 0…1 (aus snow_depth, 5 cm = voll)
    var snowCover: Double
    /// Sonnenauf-/-untergang als Ortszeit-Stunde dieses Macs (Kommazahl)
    var sunrise: Double?
    var sunset: Double?
    var fetched: Date

    var sunTimes: (rise: Double, set: Double)? { sunrise.flatMap { r in sunset.map { (r, $0) } } }

    /// Wie trüb es ist: färbt den Himmel grau, dämpft Sonne und Sonnenflecken, macht drinnen das Licht an.
    var gloom: Double {
        let base: Double
        switch kind {
        case .clear: base = 0
        case .partly: base = 0.12
        case .cloudy: base = 0.45
        case .fog: base = 0.5
        case .drizzle: base = 0.5
        case .rain: base = 0.62
        case .thunder: base = 0.85
        case .snow: base = 0.45
        }
        return max(base, (cloudCover - 0.55) * 0.9)
    }
    var raining: Bool { kind == .drizzle || kind == .rain || kind == .thunder }

    /// WMO-Wettercode (Open-Meteo) → Art + Stärke
    static func from(code: Int) -> (Kind, Double) {
        switch code {
        case 0: return (.clear, 0)
        case 1, 2: return (.partly, 0)
        case 3: return (.cloudy, 0)
        case 45, 48: return (.fog, 0)
        case 51, 53, 55, 56, 57: return (.drizzle, code == 51 ? 0.25 : code == 53 ? 0.35 : 0.45)
        case 61, 66, 80: return (.rain, 0.5)
        case 63, 81: return (.rain, 0.75)
        case 65, 67, 82: return (.rain, 1)
        case 71, 77, 85: return (.snow, 0.45)
        case 73: return (.snow, 0.7)
        case 75, 86: return (.snow, 1)
        case 95: return (.thunder, 0.8)
        case 96, 99: return (.thunder, 1)
        default: return (.cloudy, 0)
        }
    }

    var symbol: String {
        switch kind {
        case .clear: return "sun.max.fill"
        case .partly: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        case .snow: return "cloud.snow.fill"
        }
    }

    /// Zum Testen und für Screenshots: AGENTBAR_FAKE_WEATHER=snow[,temp] (Art aus Kind, optional Temperatur)
    static var fake: Weather? {
        guard let v = ProcessInfo.processInfo.environment["AGENTBAR_FAKE_WEATHER"], !v.isEmpty else { return nil }
        return fake(v)
    }
    static func fake(_ spec: String) -> Weather? {
        let parts = spec.split(separator: ",").map(String.init)
        guard let kind = Kind(rawValue: parts[0]) else { return nil }
        let temp = parts.count > 1 ? Double(parts[1]) ?? 10 : (kind == .snow ? -2 : 12)
        let cover: Double = [.clear: 0.05, .partly: 0.4][kind] ?? 0.95
        let intensity: Double = [.drizzle: 0.35, .rain: 0.75, .thunder: 1, .snow: 0.7][kind] ?? 0
        return Weather(kind: kind, intensity: intensity, cloudCover: cover, temperature: temp, wind: kind == .thunder ? 35 : 12,
                       snowCover: kind == .snow ? 1 : 0, sunrise: nil, sunset: nil, fetched: Date())
    }
}

/// Holt das Wetter für den eingetragenen Ort bei Open-Meteo (kostenlos, ohne Schlüssel).
/// Übertragen werden nur die auf zwei Nachkommastellen (~1 km) gerundeten Koordinaten.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var current: Weather?
    @Published private(set) var lastError: String?
    private var timer: Timer?
    private var loading = false

    /// Ohne Netz bleibt das letzte Wetter stehen, aber nicht ewig
    private static let maxAge: TimeInterval = 3 * 3600
    private static let refresh: TimeInterval = 30 * 60

    init() {
        if let d = UserDefaults.standard.data(forKey: Prefs.weatherCache),
           let w = try? JSONDecoder().decode(Weather.self, from: d),
           Date().timeIntervalSince(w.fetched) < Self.maxAge {
            current = w
        }
        if let f = Weather.fake { current = f }
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.weatherEnabled) && coordinates != nil }
    private var coordinates: (Double, Double)? {
        let d = UserDefaults.standard
        guard d.object(forKey: Prefs.weatherLat) != nil, d.object(forKey: Prefs.weatherLon) != nil else { return nil }
        return (d.double(forKey: Prefs.weatherLat), d.double(forKey: Prefs.weatherLon))
    }

    /// Was die Szene zeichnet: nichts, wenn ausgeschaltet, kein Ort oder zu alt.
    var shown: Weather? {
        if let f = Weather.fake { return f }
        guard enabled, let w = current, Date().timeIntervalSince(w.fetched) < Self.maxAge else { return nil }
        return w
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfNeeded() }
        }
        refreshIfNeeded()
    }
    func stop() { timer?.invalidate(); timer = nil }

    func refreshIfNeeded(force: Bool = false) {
        guard Weather.fake == nil, enabled, !loading else { return }
        if !force, let w = current, Date().timeIntervalSince(w.fetched) < Self.refresh { return }
        guard let (lat, lon) = coordinates else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let w = try await Self.fetch(lat: lat, lon: lon)
                current = w
                lastError = nil
                if let d = try? JSONEncoder().encode(w) { UserDefaults.standard.set(d, forKey: Prefs.weatherCache) }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Ort suchen, speichern und Wetter einschalten. Rückgabe: Anzeigename oder nil (nicht gefunden).
    func setPlace(_ query: String) async -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let place = try? await Self.geocode(q) else { return nil }
        let d = UserDefaults.standard
        d.set(place.name, forKey: Prefs.weatherPlace)
        d.set(place.lat, forKey: Prefs.weatherLat)
        d.set(place.lon, forKey: Prefs.weatherLon)
        d.set(true, forKey: Prefs.weatherEnabled)
        d.removeObject(forKey: Prefs.weatherCache)
        current = nil
        refreshIfNeeded(force: true)
        return place.name
    }

    func clearPlace() {
        let d = UserDefaults.standard
        for k in [Prefs.weatherPlace, Prefs.weatherLat, Prefs.weatherLon, Prefs.weatherCache] { d.removeObject(forKey: k) }
        d.set(false, forKey: Prefs.weatherEnabled)
        current = nil
    }

    // MARK: Open-Meteo

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private static func geocode(_ name: String) async throws -> (name: String, lat: Double, lon: Double)? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "1"),
                        .init(name: "language", value: Lang.isGerman ? "de" : "en"), .init(name: "format", value: "json")]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = (json["results"] as? [[String: Any]])?.first,
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return nil }
        let city = r["name"] as? String ?? name
        let label = [city, r["country"] as? String].compactMap { $0 }.joined(separator: ", ")
        return (label, round2(lat), round2(lon))
    }

    private static func fetch(lat: Double, lon: Double) async throws -> Weather {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(round2(lat))), .init(name: "longitude", value: String(round2(lon))),
            .init(name: "current", value: "temperature_2m,weather_code,cloud_cover,wind_speed_10m,snow_depth"),
            .init(name: "daily", value: "sunrise,sunset"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "1"),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any] else { throw URLError(.badServerResponse) }
        let (kind, intensity) = Weather.from(code: (cur["weather_code"] as? NSNumber)?.intValue ?? 3)
        let offset = (json["utc_offset_seconds"] as? NSNumber)?.intValue ?? 0
        let daily = json["daily"] as? [String: Any]
        func localHour(_ key: String) -> Double? {
            guard let s = (daily?[key] as? [String])?.first else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            f.timeZone = TimeZone(secondsFromGMT: offset)
            guard let d = f.date(from: s) else { return nil }
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
        func num(_ k: String) -> Double { (cur[k] as? NSNumber)?.doubleValue ?? 0 }
        var sunrise = localHour("sunrise"), sunset = localHour("sunset")
        // Polartag/-nacht oder Unsinn → Standard-Tageslauf
        if let r = sunrise, let s = sunset, !(r > 2 && s < 23 && s - r > 4) { sunrise = nil; sunset = nil }
        return Weather(kind: kind, intensity: intensity, cloudCover: num("cloud_cover") / 100, temperature: num("temperature_2m"),
                       wind: num("wind_speed_10m"), snowCover: min(1, num("snow_depth") / 0.05),
                       sunrise: sunrise, sunset: sunset, fetched: Date())
    }
}
