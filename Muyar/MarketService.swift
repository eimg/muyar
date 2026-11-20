import Foundation

protocol MarketServing: Sendable {
    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot
    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries
    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage
    func p2p(buy: Bool) async throws -> P2PSide
    func search(_ query: String, crypto: Bool) async throws -> [Instrument]
}

actor MarketService: MarketServing {
    private let session: URLSession
    private var cryptoCatalog: [Instrument]?
    init(session: URLSession = .shared) { self.session = session }

    private func data(host: String, path: String, query: [String: String]) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw MarketError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 Muyar/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MarketError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw MarketError.http(response.statusCode) }
        return data
    }

    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot {
        let now = Date()
        if instrument.provider == .binance {
            async let tickerData = data(host: "data-api.binance.vision", path: "/api/v3/ticker/24hr", query: ["symbol": instrument.symbol])
            async let series = history(for: instrument, range: .day)
            let ticker = try JSONDecoder().decode(BinanceTicker.self, from: await tickerData)
            guard let price = Double(ticker.lastPrice), price.isFinite, price > 0 else { throw MarketError.noData }
            // A chart failure must not hide a valid current price.
            let chart = try? await series
            return .init(instrumentID: instrument.id, price: price, changePercent: Double(ticker.priceChangePercent), currency: instrument.currency, marketDate: Date(timeIntervalSince1970: ticker.closeTime / 1000), fetchedAt: now, marketOpen: true, points: chart?.points ?? [], candles: chart?.candles)
        }
        let raw = try await yahooChart(instrument.symbol, interval: "5m", range: "1d")
        return try MarketParsing.yahooSnapshot(raw, instrument: instrument, now: now)
    }

    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries {
        let now = Date()
        let candles: [PriceCandle]
        if instrument.provider == .binance {
            let limit = Int(ceil(range.duration / range.candleDuration)) + 2
            let raw = try await data(host: "data-api.binance.vision", path: "/api/v3/klines", query: ["symbol": instrument.symbol, "interval": range.interval, "limit": String(min(limit, 1000))])
            candles = try MarketParsing.binanceCandles(raw)
        } else {
            let raw = try await yahooChart(instrument.symbol, interval: range.yahooInterval, range: range.yahooRange)
            candles = try MarketParsing.yahooResult(raw).candles
        }
        let visible = candles.filter { range.contains($0.date, now: now) }
        return .init(candles: CandleAggregation.aggregate(visible, interval: range.candleDuration), fetchedAt: now)
    }

    private func yahooChart(_ symbol: String, interval: String, range: String) async throws -> Data {
        try await data(host: "query1.finance.yahoo.com", path: "/v8/finance/chart/\(symbol)", query: ["interval": interval, "range": range, "includePrePost": "false"])
    }

    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage {
        let now = Date()
        let end = min(before, now)
        let earliest = ChartHistoryPolicy.earliest(provider: instrument.provider, range: range, now: now)
        guard end > earliest else { return .init(samples: [], fetchedAt: now, nextBefore: nil) }
        let lower = max(earliest, end.addingTimeInterval(-ChartHistoryPolicy.pageSpan(provider: instrument.provider, range: range)))
        // Do not split an aggregated candle across two historical pages.
        let start = Date(timeIntervalSince1970: ceil(lower.timeIntervalSince1970 / range.candleDuration) * range.candleDuration)
        guard start < end else { return .init(samples: [], fetchedAt: now, nextBefore: nil) }
        let candles: [PriceCandle]
        let points: [PricePoint]
        var firstTradeDate: Date?
        if instrument.provider == .binance {
            let raw = try await data(host: "data-api.binance.vision", path: "/api/v3/klines", query: [
                "symbol": instrument.symbol, "interval": range.interval, "limit": String(ChartHistoryPolicy.pageSize),
                "startTime": String(Int64(ceil(start.timeIntervalSince1970 * 1000))),
                "endTime": String(Int64(ceil(end.timeIntervalSince1970 * 1000)) - 1)
            ])
            candles = try MarketParsing.binanceCandles(raw)
            points = candles.map(\.closePoint)
        } else {
            let raw = try await data(host: "query1.finance.yahoo.com", path: "/v8/finance/chart/\(instrument.symbol)", query: [
                "interval": range.yahooInterval, "period1": String(Int(start.timeIntervalSince1970)),
                "period2": String(Int(ceil(end.timeIntervalSince1970))), "includePrePost": "false"
            ])
            let result = try MarketParsing.yahooResult(raw)
            candles = result.candles
            points = result.points
            firstTradeDate = result.meta.firstTradeDate.map(Date.init(timeIntervalSince1970:))
        }
        let inWindow: (Date) -> Bool = { $0 >= start && $0 < end }
        let all = ChartHistoryPolicy.samples(points: points.filter { inWindow($0.date) }, candles: candles.filter { inWindow($0.date) }, interval: range.candleDuration)
        let samples = Array(all.suffix(ChartHistoryPolicy.pageSize))
        let lowerBound = max(earliest, firstTradeDate ?? earliest)
        let candidate = all.count >= ChartHistoryPolicy.pageSize ? samples.first!.date : start
        let next: Date?
        if instrument.provider == .binance, all.isEmpty { next = nil }
        else { next = candidate > lowerBound && candidate < end ? candidate : nil }
        return .init(samples: samples, fetchedAt: Date(), nextBefore: next)
    }

    func p2p(buy: Bool) async throws -> P2PSide {
        let raw = try await data(host: "www.binance.com", path: "/bapi/c2c/v1/public/c2c/agent/quote-price", query: ["fiat": "MMK", "asset": "USDT", "tradeType": buy ? "BUY" : "SELL"])
        return try MarketParsing.p2p(raw, now: Date())
    }

    func search(_ query: String, crypto: Bool) async throws -> [Instrument] {
        if crypto {
            if cryptoCatalog == nil {
                let raw = try await data(host: "data-api.binance.vision", path: "/api/v3/exchangeInfo", query: ["permissions": "SPOT"])
                let catalog = try JSONDecoder().decode(BinanceCatalog.self, from: raw)
                cryptoCatalog = catalog.symbols.filter { $0.status == "TRADING" && $0.isSpotTradingAllowed }.map {
                    Instrument(symbol: $0.symbol, name: $0.baseAsset, category: .crypto, provider: .binance, currency: $0.quoteAsset, exchange: "Binance", unit: nil)
                }
            }
            let term = query.uppercased().replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: "")
            let namedMatches = Set(Instrument.suggestions.filter { $0.provider == .binance && $0.name.localizedCaseInsensitiveContains(query) }.map(\.symbol))
            return (cryptoCatalog ?? []).filter { $0.symbol.contains(term) || namedMatches.contains($0.symbol) }.sorted {
                let left = $0.symbol == term ? 0 : ($0.currency == "USDT" ? 1 : 2)
                let right = $1.symbol == term ? 0 : ($1.currency == "USDT" ? 1 : 2)
                return left == right ? $0.symbol < $1.symbol : left < right
            }.prefix(40).map { $0 }
        }
        let raw = try await data(host: "query1.finance.yahoo.com", path: "/v1/finance/search", query: ["q": query, "quotesCount": "20", "newsCount": "0"])
        let response = try JSONDecoder().decode(YahooSearch.self, from: raw)
        return response.quotes.compactMap { result in
            guard ["EQUITY", "ETF", "INDEX", "FUTURE", "CURRENCY"].contains(result.quoteType ?? "") else { return nil }
            if let known = Instrument.suggestions.first(where: { $0.symbol == result.symbol }) { return known }
            // Unknown futures must not be silently presented as stocks.
            guard ["EQUITY", "ETF", "INDEX"].contains(result.quoteType ?? "") else { return nil }
            return Instrument(symbol: result.symbol, name: result.longname ?? result.shortname ?? result.symbol, category: .stocks, provider: .yahoo, currency: "", exchange: result.exchDisp ?? result.exchange ?? "", unit: nil)
        }
    }
}

enum MarketParsing {
    static func binancePoints(_ data: Data) throws -> [PricePoint] {
        try binanceCandles(data).map(\.closePoint)
    }

    static func binanceCandles(_ data: Data) throws -> [PriceCandle] {
        let rows = try JSONDecoder().decode([BinanceCandle].self, from: data)
        return rows.compactMap { candle in
            guard let open = Double(candle.open), let high = Double(candle.high),
                  let low = Double(candle.low), let close = Double(candle.close),
                  open > 0, high > 0, low > 0, close > 0 else { return nil }
            let result = PriceCandle(date: Date(timeIntervalSince1970: candle.openTime / 1000), open: open, high: high, low: low, close: close)
            return result.isValid ? result : nil
        }.sorted { $0.date < $1.date }
    }

    static func yahooResult(_ data: Data) throws -> YahooChartResult {
        let response = try JSONDecoder().decode(YahooChart.self, from: data)
        if let error = response.chart.error { throw MarketError.service(error.description ?? "Symbol unavailable.") }
        guard let result = response.chart.result?.first else { throw MarketError.noData }
        return result
    }

    static func yahooSnapshot(_ data: Data, instrument: Instrument, now: Date) throws -> MarketSnapshot {
        let result = try yahooResult(data)
        let meta = result.meta
        guard let price = meta.regularMarketPrice, price.isFinite, price > 0,
              let timestamp = meta.regularMarketTime else { throw MarketError.noData }
        let previousClose = meta.previousClose ?? meta.chartPreviousClose
        let change = previousClose.flatMap { $0 > 0 ? (price - $0) / $0 * 100 : nil }
        let regular = meta.currentTradingPeriod?.regular
        let open = regular.map { now.timeIntervalSince1970 >= $0.start && now.timeIntervalSince1970 < $0.end } ?? false
        let candles = result.candles.filter { ChartRange.day.contains($0.date, now: now) }
        return .init(instrumentID: instrument.id, price: price, changePercent: change, currency: meta.currency ?? instrument.currency, marketDate: Date(timeIntervalSince1970: timestamp), fetchedAt: now, marketOpen: open, points: result.points.filter { ChartRange.day.contains($0.date, now: now) }, candles: CandleAggregation.aggregate(candles, interval: ChartRange.day.candleDuration))
    }

    static func p2p(_ data: Data, now: Date) throws -> P2PSide {
        let response = try JSONDecoder().decode(P2PResponse.self, from: data)
        guard response.success, response.code == "000000", let quote = response.data,
              quote.asset == "USDT", quote.fiat == "MMK", quote.price.isFinite, quote.price > 0 else {
            throw MarketError.noData
        }
        return .init(price: quote.price, fetchedAt: now)
    }
}

private struct BinanceTicker: Decodable {
    let lastPrice: String
    let priceChangePercent: String
    let closeTime: Double
}

private struct BinanceCandle: Decodable {
    let openTime: Double
    let open: String
    let high: String
    let low: String
    let close: String
    init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        openTime = try row.decode(Double.self)
        open = try row.decode(String.self)
        high = try row.decode(String.self)
        low = try row.decode(String.self)
        close = try row.decode(String.self)
    }
}

private struct BinanceCatalog: Decodable {
    let symbols: [Symbol]
    struct Symbol: Decodable {
        let symbol: String, status: String, baseAsset: String, quoteAsset: String
        let isSpotTradingAllowed: Bool
    }
}

private struct P2PResponse: Decodable {
    let code: String
    let success: Bool
    let data: Quote?
    struct Quote: Decodable {
        let asset: String, fiat: String
        let price: Double
    }
}

struct YahooChart: Decodable {
    let chart: Body
    struct Body: Decodable {
        let result: [YahooChartResult]?
        let error: Failure?
    }
    struct Failure: Decodable { let description: String? }
}

struct YahooChartResult: Decodable {
    let meta: Meta
    let timestamp: [Double]?
    let indicators: Indicators?
    struct Meta: Decodable {
        let currency: String?
        let regularMarketPrice: Double?
        let regularMarketTime: Double?
        let previousClose: Double?
        let chartPreviousClose: Double?
        let currentTradingPeriod: TradingPeriod?
        let firstTradeDate: Double?
    }
    struct TradingPeriod: Decodable { let regular: Period }
    struct Period: Decodable { let start: Double, end: Double }
    struct Indicators: Decodable { let quote: [Quote]? }
    struct Quote: Decodable {
        let open: [Double?]?
        let high: [Double?]?
        let low: [Double?]?
        let close: [Double?]?
    }
    var candles: [PriceCandle] {
        guard let times = timestamp, let quote = indicators?.quote?.first,
              let opens = quote.open, let highs = quote.high, let lows = quote.low, let closes = quote.close else { return [] }
        return times.indices.compactMap { index in
            guard index < opens.count, index < highs.count, index < lows.count, index < closes.count,
                  let open = opens[index], let high = highs[index], let low = lows[index], let close = closes[index] else { return nil }
            let candle = PriceCandle(date: Date(timeIntervalSince1970: times[index]), open: open, high: high, low: low, close: close)
            return candle.isValid ? candle : nil
        }.sorted { $0.date < $1.date }
    }
    var points: [PricePoint] {
        guard let times = timestamp, let closes = indicators?.quote?.first?.close else { return [] }
        return zip(times, closes).compactMap { time, close in
            guard let close, close.isFinite, close > 0 else { return nil }
            return PricePoint(date: Date(timeIntervalSince1970: time), value: close)
        }.sorted { $0.date < $1.date }
    }
}

private struct YahooSearch: Decodable {
    let quotes: [Quote]
    struct Quote: Decodable {
        let symbol: String
        let shortname: String?
        let longname: String?
        let quoteType: String?
        let exchange: String?
        let exchDisp: String?
    }
}
