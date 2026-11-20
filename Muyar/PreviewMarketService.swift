import Foundation

#if DEBUG
/// Deterministic data is only available to explicitly launched UI tests.
struct PreviewMarketService: MarketServing {
    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot {
        let prices: [String: Double] = ["GC=F": 3526.30, "CL=F": 83.04, "BTCUSDT": 61534.61, "ETHUSDT": 2138.42, "AAPL": 349.21, "NVDA": 178.65]
        let price = prices[instrument.symbol] ?? 241.16
        let series = try await history(for: instrument, range: .day)
        return .init(instrumentID: instrument.id, price: price, changePercent: instrument.category == .energy ? -0.73 : 1.42, currency: instrument.currency.isEmpty ? "USD" : instrument.currency, marketDate: Date().addingTimeInterval(-60), fetchedAt: Date(), marketOpen: instrument.provider == .binance, points: series.points, candles: series.candles)
    }
    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries {
        let prices: [String: Double] = ["GC=F": 3526.30, "CL=F": 83.04, "BTCUSDT": 61534.61, "ETHUSDT": 2138.42, "AAPL": 349.21, "NVDA": 178.65]
        let base = prices[instrument.symbol] ?? 241.16
        let now = Date()
        let count = Int(range.duration / range.candleDuration)
        let candles: [PriceCandle] = (0..<count).map { index in
            let step = Double(index)
            let date = now.addingTimeInterval(-range.duration + step * range.candleDuration)
            let trend = 0.98 + step * 0.00025
            let wave = sin(step * 0.48) * 0.003 + cos(step * 1.1) * 0.001
            let open = base * (trend + wave)
            let close = open + base * sin(step * 1.7) * 0.0025
            let high = max(open, close) + base * 0.0015
            let low = min(open, close) - base * 0.0012
            return PriceCandle(date: date, open: open, high: high, low: low, close: close)
        }
        return .init(candles: candles, fetchedAt: now)
    }
    func p2p(buy: Bool) async throws -> P2PSide { .init(price: buy ? 5160 : 5148, fetchedAt: Date()) }
    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage {
        let earliest = ChartHistoryPolicy.earliest(provider: instrument.provider, range: range)
        guard before > earliest else { return .init(samples: [], fetchedAt: Date(), nextBefore: nil) }
        let end = floor(before.timeIntervalSince1970 / range.candleDuration) * range.candleDuration
        let base: Double = instrument.symbol == "BTCUSDT" ? 61534 : (instrument.symbol == "AAPL" ? 349 : 3526)
        let candles: [PriceCandle] = (0..<200).map { index in
            let time = end - Double(200 - index) * range.candleDuration
            let phase = time / range.candleDuration
            let open = base * (1 + sin(phase * 0.15) * 0.02)
            let close = open + base * sin(phase * 1.7) * 0.0025
            return .init(date: Date(timeIntervalSince1970: time), open: open, high: max(open, close) + base * 0.0015, low: min(open, close) - base * 0.0012, close: close)
        }.filter { $0.date >= earliest }
        let samples = candles.map { ChartSample(date: $0.date, close: $0.close, candle: $0) }
        return .init(samples: samples, fetchedAt: Date(), nextBefore: samples.first.flatMap { $0.date > earliest ? $0.date : nil })
    }
    func p2pOffers(side: P2PTradeSide) async throws -> P2POfferBook {
        if ProcessInfo.processInfo.arguments.contains("-empty-p2p-offers") {
            return .init(side: side, offers: [], fetchedAt: Date(), returnedCount: 0, omittedCount: 0)
        }
        let offers = (0..<5).map { index in
            P2POffer(id: "sample-\(side.rawValue)-\(index)", price: Double(side == .buy ? 5160 + index * 2 : 5148 - index * 2),
                     merchant: "Sample \(side.counterparty) \(index + 1)", minMMK: Double(100000 * (index + 1)), maxMMK: 5000000,
                     availableUSDT: Double(8000 - index * 750), paymentMethods: index.isMultiple(of: 2) ? ["KBZPay", "Bank Transfer"] : ["WavePay"],
                     completionRate: 0.998, monthlyOrders: 230 + index * 11)
        }
        return .init(side: side, offers: offers, fetchedAt: Date(), returnedCount: 5, omittedCount: 0)
    }
    func search(_ query: String, crypto: Bool) async throws -> [Instrument] {
        Instrument.suggestions.filter {
            ($0.provider == .binance) == crypto && ($0.symbol.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query))
        }
    }
}
#endif
