import Foundation

enum AssetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case metals = "Metals", energy = "Energy", stocks = "Stocks", crypto = "Crypto"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .metals: "circle.hexagongrid.fill"
        case .energy: "drop.fill"
        case .stocks: "chart.bar.fill"
        case .crypto: "bitcoinsign"
        }
    }
}

enum MarketProvider: String, Codable, Sendable {
    case binance, yahoo
    var name: String { self == .binance ? "Binance Spot" : "Yahoo Finance" }
}

struct Instrument: Identifiable, Codable, Equatable, Hashable, Sendable {
    let symbol: String
    let name: String
    let category: AssetCategory
    let provider: MarketProvider
    let currency: String
    let exchange: String
    let unit: String?

    var id: String { "\(provider.rawValue):\(symbol)" }
    var displaySymbol: String {
        guard provider == .binance else { return symbol }
        for quote in ["USDT", "USDC", "FDUSD", "BTC", "ETH", "EUR", "TRY", "BNB"] {
            if symbol.hasSuffix(quote), symbol.count > quote.count {
                return "\(symbol.dropLast(quote.count))/\(quote)"
            }
        }
        return symbol
    }
    var monogram: String {
        switch symbol {
        case "GC=F": "Au"
        case "SI=F": "Ag"
        case "CL=F", "BZ=F": "Oil"
        default: String(symbol.prefix(provider == .binance ? 1 : 2))
        }
    }
    static let defaults: [Instrument] = [
        .init(symbol: "GC=F", name: "Gold futures", category: .metals, provider: .yahoo, currency: "USD", exchange: "COMEX", unit: "troy oz"),
        .init(symbol: "CL=F", name: "WTI crude futures", category: .energy, provider: .yahoo, currency: "USD", exchange: "NYMEX", unit: "barrel"),
        .init(symbol: "BTCUSDT", name: "Bitcoin", category: .crypto, provider: .binance, currency: "USDT", exchange: "Binance", unit: nil),
        .init(symbol: "ETHUSDT", name: "Ethereum", category: .crypto, provider: .binance, currency: "USDT", exchange: "Binance", unit: nil),
        .init(symbol: "AAPL", name: "Apple", category: .stocks, provider: .yahoo, currency: "USD", exchange: "NASDAQ", unit: nil),
        .init(symbol: "NVDA", name: "NVIDIA", category: .stocks, provider: .yahoo, currency: "USD", exchange: "NASDAQ", unit: nil)
    ]
    static let suggestions: [Instrument] = defaults + [
        .init(symbol: "MSFT", name: "Microsoft", category: .stocks, provider: .yahoo, currency: "USD", exchange: "NASDAQ", unit: nil),
        .init(symbol: "TSLA", name: "Tesla", category: .stocks, provider: .yahoo, currency: "USD", exchange: "NASDAQ", unit: nil),
        .init(symbol: "SPY", name: "SPDR S&P 500 ETF", category: .stocks, provider: .yahoo, currency: "USD", exchange: "NYSE Arca", unit: nil),
        .init(symbol: "BZ=F", name: "Brent crude futures", category: .energy, provider: .yahoo, currency: "USD", exchange: "ICE", unit: "barrel"),
        .init(symbol: "SI=F", name: "Silver futures", category: .metals, provider: .yahoo, currency: "USD", exchange: "COMEX", unit: "troy oz"),
        .init(symbol: "SOLUSDT", name: "Solana", category: .crypto, provider: .binance, currency: "USDT", exchange: "Binance", unit: nil)
    ]
}

enum ChartRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case fourHours = "4H", day = "1D", week = "1W", month = "1M"
    var id: String { rawValue }
    var duration: TimeInterval {
        switch self {
        case .fourHours: 4 * 3600
        case .day: 24 * 3600
        case .week: 7 * 86400
        case .month: 30 * 86400
        }
    }
    var interval: String {
        switch self {
        case .fourHours: "5m"
        case .day: "30m"
        case .week: "4h"
        case .month: "1d"
        }
    }
    var candleDuration: TimeInterval {
        switch self {
        case .fourHours: 300
        case .day: 1800
        case .week: 14400
        case .month: 86400
        }
    }
    var candleLabel: String { self == .month ? "1D" : interval }
    var yahooInterval: String { self == .week ? "1h" : interval }
    var yahooRange: String {
        switch self {
        case .fourHours, .day: "5d"
        case .week, .month: "1mo"
        }
    }
    var description: String {
        switch self {
        case .fourHours: "past 4 hours"
        case .day: "past 24 hours"
        case .week: "past 7 days"
        case .month: "past 30 days"
        }
    }
    func contains(_ date: Date, now: Date) -> Bool {
        date >= now.addingTimeInterval(-duration) && date <= now
    }
}

struct PricePoint: Identifiable, Codable, Equatable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct PriceCandle: Identifiable, Codable, Equatable, Sendable {
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    var id: Date { date }
    var isValid: Bool {
        date.timeIntervalSince1970.isFinite && [open, high, low, close].allSatisfy(\.isFinite)
            && low <= min(open, close) && high >= max(open, close) && low <= high
    }
    var closePoint: PricePoint { .init(date: date, value: close) }
}

enum CandleAggregation {
    /// Combine real source bars only. Missing sessions remain gaps.
    static func aggregate(_ candles: [PriceCandle], interval: TimeInterval) -> [PriceCandle] {
        guard interval.isFinite, interval > 0 else { return [] }
        let groups = Dictionary(grouping: candles.filter(\.isValid)) {
            floor($0.date.timeIntervalSince1970 / interval)
        }
        return groups.values.compactMap { group -> PriceCandle? in
            let sorted = group.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            return .init(date: first.date, open: first.open, high: sorted.map(\.high).max()!,
                         low: sorted.map(\.low).min()!, close: last.close)
        }.sorted { $0.date < $1.date }
    }
}

struct MarketSnapshot: Codable, Sendable {
    let instrumentID: String
    let price: Double
    let changePercent: Double?
    let currency: String
    let marketDate: Date
    let fetchedAt: Date
    let marketOpen: Bool
    let points: [PricePoint]
    let candles: [PriceCandle]?

    init(instrumentID: String, price: Double, changePercent: Double?, currency: String,
         marketDate: Date, fetchedAt: Date, marketOpen: Bool, points: [PricePoint], candles: [PriceCandle]? = nil) {
        self.instrumentID = instrumentID
        self.price = price
        self.changePercent = changePercent
        self.currency = currency
        self.marketDate = marketDate
        self.fetchedAt = fetchedAt
        self.marketOpen = marketOpen
        self.points = points
        self.candles = candles
    }

    func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(fetchedAt) > 600 }
    var changeLabel: String { instrumentID.hasPrefix("binance:") ? "24h" : "vs prev. close" }
}

struct ChartSeries: Sendable {
    let points: [PricePoint]
    let candles: [PriceCandle]
    let fetchedAt: Date

    init(points: [PricePoint], fetchedAt: Date) {
        self.points = points
        self.candles = []
        self.fetchedAt = fetchedAt
    }
    init(candles: [PriceCandle], fetchedAt: Date) {
        self.candles = candles.filter(\.isValid).sorted { $0.date < $1.date }
        self.points = self.candles.map(\.closePoint)
        self.fetchedAt = fetchedAt
    }
    var changePercent: Double? {
        if let first = candles.first, let last = candles.last, first.open > 0 {
            return (last.close - first.open) / first.open * 100
        }
        guard let first = points.first?.value, let last = points.last?.value, first > 0, points.count > 1 else { return nil }
        return (last - first) / first * 100
    }
    var domain: ClosedRange<Double> {
        let low = candles.map(\.low).min() ?? points.map(\.value).min() ?? 0
        let high = candles.map(\.high).max() ?? points.map(\.value).max() ?? 1
        let padding = max((high - low) * 0.16, abs(high) * 0.001, 0.000001)
        return (low - padding)...(high + padding)
    }
}

struct P2PSide: Codable, Sendable {
    let price: Double
    let fetchedAt: Date
}

struct P2PQuotes: Codable, Sendable {
    var buy: P2PSide?
    var sell: P2PSide?
}

enum MarketError: LocalizedError {
    case invalidResponse, noData, service(String), http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response"
        case .noData: "No data"
        case .service(let message): message
        case .http(let code):
            switch code {
            case 429: "Rate limited"
            case 403, 451: "Source unavailable"
            default: "HTTP \(code)"
            }
        }
    }
}

enum PriceFormat {
    static func number(_ value: Double, currency: String = "USD") -> String {
        let digits = currency == "MMK" ? 0 : (abs(value) < 0.01 ? 6 : (abs(value) < 1 ? 4 : 2))
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
    static func price(_ value: Double, currency: String = "USD") -> String {
        let prefix = currency == "USD" ? "$" : ""
        return prefix + number(value, currency: currency)
    }
    static func change(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}
