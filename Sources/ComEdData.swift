import Foundation

// MARK: - Model

/// A single hourly price point. `predicted` distinguishes day-ahead forecast
/// bars from actual settled averages.
public struct PricePoint: Identifiable, Hashable, Codable {
    public var hour: Date          // start of the hour, in absolute time
    public var cents: Double       // price in cents/kWh
    public var predicted: Bool
    public var id: Date { hour }

    public init(hour: Date, cents: Double, predicted: Bool) {
        self.hour = hour
        self.cents = cents
        self.predicted = predicted
    }
}

/// Everything the widget view needs for one render.
public struct PriceSnapshot: Codable {
    public var current: Double          // current-hour average, cents/kWh
    public var asOf: Date               // when we fetched / newest data time
    public var points: [PricePoint]     // actuals + predictions, sorted by hour
    public var stale: Bool              // true if network failed and this is fallback

    public init(current: Double, asOf: Date, points: [PricePoint], stale: Bool) {
        self.current = current
        self.asOf = asOf
        self.points = points
        self.stale = stale
    }

    public static var placeholder: PriceSnapshot {
        let cal = Calendar.central
        let now = cal.startOfHour(Date())
        var pts: [PricePoint] = []
        for i in -8...8 {
            let h = cal.date(byAdding: .hour, value: i, to: now)!
            pts.append(PricePoint(hour: h, cents: 5 + Double(i) * 0.3, predicted: i > 0))
        }
        return PriceSnapshot(current: 6.1, asOf: now, points: pts, stale: false)
    }
}

// MARK: - Time helpers

public extension TimeZone {
    static let central = TimeZone(identifier: "America/Chicago")!
}

public extension Calendar {
    static var central: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .central
        return c
    }
    func startOfHour(_ d: Date) -> Date {
        let comps = dateComponents([.year, .month, .day, .hour], from: d)
        return date(from: comps)!
    }
}

// MARK: - Fetching

public enum ComEd {
    static let currentURL = URL(string: "https://hourlypricing.comed.com/api?type=currenthouraverage")!
    static let dayURL     = URL(string: "https://hourlypricing.comed.com/api?type=day")!
    static let fiveMinURL = URL(string: "https://hourlypricing.comed.com/api?type=5minutefeed")!

    static func dayAheadURL(for date: Date) -> URL {
        let f = DateFormatter()
        f.timeZone = .central
        f.dateFormat = "yyyyMMdd"
        let d = f.string(from: date)
        return URL(string: "https://hourlypricing.comed.com/rrtp/ServletFeed?type=daynexttoday&date=\(d)")!
    }

    // Simple {millisUTC, price} array feeds.
    struct Tick: Decodable { let millisUTC: String; let price: String }

    static func fetchData(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return data
        } catch {
            return nil
        }
    }

    static func fetchCurrent() async -> Double? {
        guard let data = await fetchData(currentURL),
              let ticks = try? JSONDecoder().decode([Tick].self, from: data),
              let first = ticks.first else { return nil }
        return Double(first.price)
    }

    /// Parse a Highcharts-style feed: `[[Date.UTC(Y,M0,D,H,0,0), price], ...]`.
    /// The Y/M/D/H are US Central *local* wall-clock values (month 0-indexed).
    static func parseHighcharts(_ text: String, predicted: Bool) -> [PricePoint] {
        let cal = Calendar.central
        // Date.UTC(2026,6,1,0,0,0), 7.3
        let pattern = #"Date\.UTC\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*\d+\s*,\s*\d+\s*\)\s*,\s*([\d.]+)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [PricePoint] = []
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges == 6 else { return }
            func g(_ i: Int) -> Int { Int(ns.substring(with: m.range(at: i))) ?? 0 }
            let year = g(1), month0 = g(2), day = g(3), hour = g(4)
            let price = Double(ns.substring(with: m.range(at: 5))) ?? 0
            var comps = DateComponents()
            comps.year = year; comps.month = month0 + 1; comps.day = day; comps.hour = hour
            comps.timeZone = .central
            if let date = cal.date(from: comps) {
                out.append(PricePoint(hour: date, cents: price, predicted: predicted))
            }
        }
        return out
    }

    static func fetchDayActuals() async -> [PricePoint] {
        guard let data = await fetchData(dayURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parseHighcharts(text, predicted: false)
    }

    static func fetchDayAhead(for date: Date) async -> [PricePoint] {
        guard let data = await fetchData(dayAheadURL(for: date)),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parseHighcharts(text, predicted: true)
    }

    /// Build the full snapshot: current-hour value + actuals (today + yesterday
    /// tail from 5-min feed) + day-ahead predictions for today and tomorrow.
    public static func fetchSnapshot() async -> PriceSnapshot {
        let cal = Calendar.central
        let now = Date()
        let thisHour = cal.startOfHour(now)

        async let currentA = fetchCurrent()
        async let actualsA = fetchDayActuals()
        async let aheadTodayA = fetchDayAhead(for: now)
        async let aheadTomorrowA = fetchDayAhead(for: cal.date(byAdding: .day, value: 1, to: now)!)
        async let fiveMinA = fetchData(fiveMinURL)

        let current = await currentA
        var actuals = await actualsA
        let aheadToday = await aheadTodayA
        let aheadTomorrow = await aheadTomorrowA
        let fiveMinData = await fiveMinA

        // If the day feed is empty (rare), bucket the 5-min feed into hourly means.
        if actuals.isEmpty, let d = fiveMinData,
           let ticks = try? JSONDecoder().decode([Tick].self, from: d) {
            var buckets: [Date: [Double]] = [:]
            for t in ticks {
                guard let ms = Double(t.millisUTC), let p = Double(t.price) else { continue }
                let date = Date(timeIntervalSince1970: ms / 1000)
                let hr = cal.startOfHour(date)
                buckets[hr, default: []].append(p)
            }
            actuals = buckets.map { k, v in
                PricePoint(hour: k, cents: (v.reduce(0, +) / Double(v.count)), predicted: false)
            }
        }

        // Merge: actuals win for past/current hours; predictions fill the future.
        var byHour: [Date: PricePoint] = [:]
        for p in aheadToday + aheadTomorrow where p.hour > thisHour {
            byHour[p.hour] = p
        }
        for p in actuals where p.hour <= thisHour {
            byHour[p.hour] = PricePoint(hour: p.hour, cents: p.cents, predicted: false)
        }

        // Ensure the current hour has a value (use current-hour average).
        if let c = current {
            byHour[thisHour] = PricePoint(hour: thisHour, cents: c, predicted: false)
        }

        let points = byHour.values.sorted { $0.hour < $1.hour }
        let stale = current == nil && actuals.isEmpty && aheadToday.isEmpty

        let currentValue = current
            ?? byHour[thisHour]?.cents
            ?? points.last(where: { $0.hour <= thisHour })?.cents
            ?? 0

        if points.isEmpty {
            return PriceSnapshot(current: currentValue, asOf: now,
                                 points: PriceSnapshot.placeholder.points, stale: true)
        }
        return PriceSnapshot(current: currentValue, asOf: now, points: points, stale: stale)
    }
}

// MARK: - Presentation helpers

import SwiftUI

public enum PriceLevel {
    public static func color(_ cents: Double) -> Color {
        switch cents {
        case ..<5:  return .green
        case ..<10: return .orange
        default:    return .red
        }
    }
}

public extension Double {
    var centsString: String { String(format: "%.1f", self) }
}
