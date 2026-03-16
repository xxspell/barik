import SwiftUI
import CoreLocation
import AppKit

/// Weather widget that displays current weather using Open-Meteo API
struct WeatherWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var weatherManager = WeatherManager.shared

    @State private var widgetFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            if let weather = weatherManager.currentWeather {
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.multicolor)
                Text(weather.temperature)
                    .fontWeight(.semibold)
            } else {
                Image(systemName: "cloud.sun")
                    .symbolRenderingMode(.multicolor)
                if weatherManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .shadow(radius: 3)
        .cornerRadius(15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        widgetFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "weather") {
                WeatherPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            // Extract weather config from the global config
            let configData = ConfigManager.shared.globalWidgetConfig(for: "default.weather")
            var unit: String = "celsius"
            var latitude: String?
            var longitude: String?

            if let unitValue = configData["unit"]?.stringValue {
                unit = unitValue
            }

            if let latValue = configData["latitude"]?.stringValue {
                latitude = latValue
            }

            if let lonValue = configData["longitude"]?.stringValue {
                longitude = lonValue
            }

            weatherManager.updateConfiguration(unit: unit, latitude: latitude, longitude: longitude)
            weatherManager.startUpdating()
        }
        .onReceive(ConfigManager.shared.$config) { _ in
            // Update configuration when config changes
            let configData = ConfigManager.shared.globalWidgetConfig(for: "default.weather")
            var unit: String = "celsius"
            var latitude: String?
            var longitude: String?

            if let unitValue = configData["unit"]?.stringValue {
                unit = unitValue
            }

            if let latValue = configData["latitude"]?.stringValue {
                latitude = latValue
            }

            if let lonValue = configData["longitude"]?.stringValue {
                longitude = lonValue
            }

            weatherManager.updateConfiguration(unit: unit, latitude: latitude, longitude: longitude)
            // Refresh weather with new configuration
            weatherManager.fetchWeather()
        }
    }
}

// MARK: - Weather Data Models

struct CurrentWeather {
    let temperature: String
    let symbolName: String
    let condition: String
}

struct HourlyForecast {
    let time: Date
    let timeLabel: String
    let temperature: String
    let symbolName: String
    let precipitationProbability: Int?
}

// MARK: - Open-Meteo API Response

struct OpenMeteoResponse: Codable {
    let currentWeather: OpenMeteoCurrentWeather
    let hourly: OpenMeteoHourly?
    let daily: OpenMeteoDaily?

    enum CodingKeys: String, CodingKey {
        case currentWeather = "current_weather"
        case hourly
        case daily
    }
}

struct OpenMeteoCurrentWeather: Codable {
    let temperature: Double
    let weathercode: Int
}

struct OpenMeteoHourly: Codable {
    let time: [String]
    let temperature2m: [Double]
    let weathercode: [Int]
    let precipitationProbability: [Int]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case weathercode
        case precipitationProbability = "precipitation_probability"
    }
}

struct OpenMeteoDaily: Codable {
    let temperature2mMax: [Double]
    let temperature2mMin: [Double]

    enum CodingKeys: String, CodingKey {
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
    }
}

// MARK: - Weather Manager

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var currentWeather: CurrentWeather?
    @Published private(set) var hourlyForecast: [HourlyForecast] = []
    @Published private(set) var locationName: String?
    @Published private(set) var highTemp: String?
    @Published private(set) var lowTemp: String?
    @Published private(set) var precipitation: Double?
    @Published private(set) var isLoading = false

    // Configuration properties
    private var temperatureUnit: String = "celsius"
    private var customLatitude: String?
    private var customLongitude: String?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastLocation: CLLocation?
    private var updateTimer: Timer?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func updateConfiguration(unit: String, latitude: String?, longitude: String?) {
        let oldUnit = self.temperatureUnit
        let oldLat = self.customLatitude
        let oldLon = self.customLongitude

        self.temperatureUnit = unit
        self.customLatitude = latitude
        self.customLongitude = longitude

        // Refresh weather if any configuration changed
        if oldUnit != unit || oldLat != latitude || oldLon != longitude {
            // If we have custom coordinates, fetch weather for those coordinates
            if let lat = customLatitude, let lon = customLongitude {
                if let latValue = Double(lat), let lonValue = Double(lon) {
                    fetchWeatherForCoordinates(latitude: latValue, longitude: lonValue, customLocationName: nil)
                }
            } else {
                // Use location services
                locationManager.startUpdatingLocation()
            }
        }
    }

    func startUpdating() {
        // Invalidate any existing timer
        updateTimer?.invalidate()

        // Check if we have custom coordinates first
        if let lat = customLatitude, let lon = customLongitude {
            if let latValue = Double(lat), let lonValue = Double(lon) {
                fetchWeatherForCoordinates(latitude: latValue, longitude: lonValue, customLocationName: nil)

                // Update every 15 minutes with custom coordinates
                updateTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        if let lat = self?.customLatitude, let lon = self?.customLongitude,
                           let latValue = Double(lat), let lonValue = Double(lon) {
                            self?.fetchWeatherForCoordinates(latitude: latValue, longitude: lonValue, customLocationName: nil)
                        }
                    }
                }
            }
        } else {
            // Use location services
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            locationManager.startUpdatingLocation()

            // Update every 15 minutes
            updateTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.fetchWeather()
                }
            }
        }
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func fetchWeather() {
        guard let location = lastLocation else { return }

        isLoading = true

        // Reverse geocode for location name
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            if let placemark = placemarks?.first {
                Task { @MainActor in
                    self?.locationName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                }
            }
        }

        Task {
            do {
                let lat = location.coordinate.latitude
                let lon = location.coordinate.longitude
                let unitParam = temperatureUnit == "celsius" ? "celsius" : "fahrenheit"
                let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true&hourly=temperature_2m,weathercode,precipitation_probability&daily=temperature_2m_max,temperature_2m_min&temperature_unit=\(unitParam)&timezone=auto&forecast_days=1"

                guard let url = URL(string: urlString) else {
                    isLoading = false
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

                // Current weather
                let temp = Int(response.currentWeather.temperature.rounded())
                let symbol = symbolName(for: response.currentWeather.weathercode)
                let condition = conditionName(for: response.currentWeather.weathercode)
                let unitSymbol = temperatureUnit == "celsius" ? "°C" : "°F"

                self.currentWeather = CurrentWeather(
                    temperature: "\(temp)\(unitSymbol)",
                    symbolName: symbol,
                    condition: condition
                )

                // Daily high/low
                if let daily = response.daily {
                    if let high = daily.temperature2mMax.first {
                        self.highTemp = "\(Int(high.rounded()))°"
                    }
                    if let low = daily.temperature2mMin.first {
                        self.lowTemp = "\(Int(low.rounded()))°"
                    }
                }

                // Hourly forecast
                if let hourly = response.hourly {
                    let now = Date()
                    var forecasts: [HourlyForecast] = []

                    for i in 0..<min(hourly.time.count, hourly.temperature2m.count, hourly.weathercode.count) {
                        // Parse the time string manually (Open-Meteo format: "2024-01-03T14:00")
                        let timeString = hourly.time[i]
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                        formatter.timeZone = TimeZone.current

                        guard let date = formatter.date(from: timeString) else { continue }

                        // Only include future hours
                        if date > now {
                            let tempVal = Int(hourly.temperature2m[i].rounded())
                            let sym = symbolName(for: hourly.weathercode[i])
                            let precip = hourly.precipitationProbability?[safe: i]

                            let timeFormatter = DateFormatter()
                            timeFormatter.dateFormat = "ha"
                            let label = forecasts.isEmpty ? "Now" : timeFormatter.string(from: date)

                            forecasts.append(HourlyForecast(
                                time: date,
                                timeLabel: label,
                                temperature: "\(tempVal)°",
                                symbolName: sym,
                                precipitationProbability: precip
                            ))

                            if forecasts.count >= 6 { break }
                        }
                    }

                    // Set precipitation from first hour
                    if let firstPrecip = hourly.precipitationProbability?.first(where: { $0 > 0 }) {
                        self.precipitation = Double(firstPrecip) / 100.0
                    } else {
                        self.precipitation = nil
                    }

                    self.hourlyForecast = forecasts
                }
            } catch {
                print("Weather fetch error: \(error)")
            }
            isLoading = false
        }
    }

    private func fetchWeatherForCoordinates(latitude: Double, longitude: Double, customLocationName: String?) {
        isLoading = true

        // Set a custom location name if provided, otherwise we'll get it from the API response
        if let customName = customLocationName {
            self.locationName = customName
        }

        Task {
            do {
                let unitParam = temperatureUnit == "celsius" ? "celsius" : "fahrenheit"
                let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true&hourly=temperature_2m,weathercode,precipitation_probability&daily=temperature_2m_max,temperature_2m_min&temperature_unit=\(unitParam)&timezone=auto&forecast_days=1"

                guard let url = URL(string: urlString) else {
                    isLoading = false
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

                // Current weather
                let temp = Int(response.currentWeather.temperature.rounded())
                let symbol = symbolName(for: response.currentWeather.weathercode)
                let condition = conditionName(for: response.currentWeather.weathercode)
                let unitSymbol = temperatureUnit == "celsius" ? "°C" : "°F"

                self.currentWeather = CurrentWeather(
                    temperature: "\(temp)\(unitSymbol)",
                    symbolName: symbol,
                    condition: condition
                )

                // Daily high/low
                if let daily = response.daily {
                    if let high = daily.temperature2mMax.first {
                        self.highTemp = "\(Int(high.rounded()))°"
                    }
                    if let low = daily.temperature2mMin.first {
                        self.lowTemp = "\(Int(low.rounded()))°"
                    }
                }

                // Hourly forecast
                if let hourly = response.hourly {
                    let now = Date()
                    var forecasts: [HourlyForecast] = []

                    for i in 0..<min(hourly.time.count, hourly.temperature2m.count, hourly.weathercode.count) {
                        // Parse the time string manually (Open-Meteo format: "2024-01-03T14:00")
                        let timeString = hourly.time[i]
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                        formatter.timeZone = TimeZone.current

                        guard let date = formatter.date(from: timeString) else { continue }

                        // Only include future hours
                        if date > now {
                            let tempVal = Int(hourly.temperature2m[i].rounded())
                            let sym = symbolName(for: hourly.weathercode[i])
                            let precip = hourly.precipitationProbability?[safe: i]

                            let timeFormatter = DateFormatter()
                            timeFormatter.dateFormat = "ha"
                            let label = forecasts.isEmpty ? "Now" : timeFormatter.string(from: date)

                            forecasts.append(HourlyForecast(
                                time: date,
                                timeLabel: label,
                                temperature: "\(tempVal)°",
                                symbolName: sym,
                                precipitationProbability: precip
                            ))

                            if forecasts.count >= 6 { break }
                        }
                    }

                    // Set precipitation from first hour
                    if let firstPrecip = hourly.precipitationProbability?.first(where: { $0 > 0 }) {
                        self.precipitation = Double(firstPrecip) / 100.0
                    } else {
                        self.precipitation = nil
                    }

                    self.hourlyForecast = forecasts
                }

                // Get location name for custom coordinates
                if self.locationName == nil || self.locationName == "Unknown" {
                    await fetchLocationNameForCoordinates(latitude: latitude, longitude: longitude)
                }
            } catch {
                print("Weather fetch error: \(error)")
            }
            isLoading = false
        }
    }

    private func fetchLocationNameForCoordinates(latitude: Double, longitude: Double) async {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                await MainActor.run {
                    self.locationName = placemark.locality ?? placemark.administrativeArea ?? "Custom Location"
                }
            } else {
                await MainActor.run {
                    self.locationName = "Custom Location"
                }
            }
        } catch {
            print("Reverse geocode error: \(error)")
            await MainActor.run {
                self.locationName = "Custom Location"
            }
        }
    }

    /// Maps Open-Meteo weather codes to SF Symbols
    func symbolName(for code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67:
            return "cloud.rain.fill"
        case 71, 73, 75, 77:
            return "cloud.snow.fill"
        case 80, 81, 82:
            return "cloud.heavyrain.fill"
        case 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    /// Maps Open-Meteo weather codes to condition names
    func conditionName(for code: Int) -> String {
        switch code {
        case 0:
            return "Clear"
        case 1:
            return "Mainly Clear"
        case 2:
            return "Partly Cloudy"
        case 3:
            return "Overcast"
        case 45, 48:
            return "Foggy"
        case 51, 53, 55:
            return "Drizzle"
        case 56, 57:
            return "Freezing Drizzle"
        case 61, 63, 65:
            return "Rain"
        case 66, 67:
            return "Freezing Rain"
        case 71, 73, 75:
            return "Snow"
        case 77:
            return "Snow Grains"
        case 80, 81, 82:
            return "Rain Showers"
        case 85, 86:
            return "Snow Showers"
        case 95:
            return "Thunderstorm"
        case 96, 99:
            return "Thunderstorm with Hail"
        default:
            return "Unknown"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            // Only update if location changed significantly (1km)
            if lastLocation == nil || lastLocation!.distance(from: location) > 1000 {
                lastLocation = location
                fetchWeather()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized ||
            manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct WeatherWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            WeatherWidget()
        }.frame(width: 100, height: 50)
    }
}
