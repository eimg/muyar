import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

final class CandlestickTests: XCTestCase {
    func testBinancePreservesAllOHLCValuesAndMilliseconds() throws {
        let data = Data(#"[[2000000,"100","109","95","103","1"],[1000000,"90","99","88","98","1"]]"#.utf8)
        let candles = try MarketParsing.binanceCandles(data)
        XCTAssertEqual(candles.map(\.date.timeIntervalSince1970), [1000, 2000])
        XCTAssertEqual(candles[1].open, 100)
        XCTAssertEqual(candles[1].high, 109)
        XCTAssertEqual(candles[1].low, 95)
        XCTAssertEqual(candles[1].close, 103)
    }

    func testInvalidSpotCandlesAreNotPlotted() throws {
        let data = Data(#"[[1000,"100","90","95","103"],[2000,"100","105","101","103"],[3000,"NaN","105","95","103"],[4000,"100","105","95","0"],[5000,"100","110","90","105"]]"#.utf8)
        let candles = try MarketParsing.binanceCandles(data)
        XCTAssertEqual(candles.count, 1)
        XCTAssertEqual(candles.first?.date.timeIntervalSince1970, 5)
    }

    func testYahooNullAndUnequalArraysDoNotShiftOHLCToAnotherTime() throws {
        let data = Data(#"{"chart":{"result":[{"meta":{},"timestamp":[10,20,30,40,50],"indicators":{"quote":[{"open":[100,null,102,103,104],"high":[105,null,105,106],"low":[95,null,101,102],"close":[103,104,104,null,105]}]}}],"error":null}}"#.utf8)
        let candles = try MarketParsing.yahooResult(data).candles
        XCTAssertEqual(candles.map(\.date.timeIntervalSince1970), [10, 30])
        XCTAssertEqual(candles[1], .init(date: Date(timeIntervalSince1970: 30), open: 102, high: 105, low: 101, close: 104))
    }

    func testCloseOnlyDataCannotBecomeFabricatedCandles() throws {
        let data = Data(#"{"chart":{"result":[{"meta":{},"timestamp":[10,20],"indicators":{"quote":[{"close":[100,102]}]}}],"error":null}}"#.utf8)
        let result = try MarketParsing.yahooResult(data)
        XCTAssertEqual(result.points.count, 2)
        XCTAssertTrue(result.candles.isEmpty)
        let legacySeries = ChartSeries(points: result.points, fetchedAt: Date())
        XCTAssertTrue(legacySeries.candles.isEmpty)
    }

    func testFourHourAggregationPreservesExtremesAndDoesNotFillMissingBuckets() {
        let source: [PriceCandle] = [
            .init(date: Date(timeIntervalSince1970: 0), open: 100, high: 105, low: 98, close: 102),
            .init(date: Date(timeIntervalSince1970: 3600), open: 102, high: 107, low: 101, close: 103),
            .init(date: Date(timeIntervalSince1970: 7200), open: 103, high: 108, low: 99, close: 100),
            .init(date: Date(timeIntervalSince1970: 10800), open: 100, high: 104, low: 97, close: 104),
            .init(date: Date(timeIntervalSince1970: 28800), open: 104, high: 110, low: 103, close: 109)
        ]
        let candles = CandleAggregation.aggregate(source.reversed(), interval: 14400)
        XCTAssertEqual(candles.count, 2)
        XCTAssertEqual(candles[0], .init(date: Date(timeIntervalSince1970: 0), open: 100, high: 108, low: 97, close: 104))
        XCTAssertEqual(candles[1].date.timeIntervalSince1970, 28800)
    }

    func testYDomainIncludesWicksRatherThanOnlyClosingPrices() {
        let candle = PriceCandle(date: Date(), open: 100, high: 150, low: 50, close: 101)
        let series = ChartSeries(candles: [candle], fetchedAt: Date())
        XCTAssertLessThan(series.domain.lowerBound, 50)
        XCTAssertGreaterThan(series.domain.upperBound, 150)
    }

    func testDojiKeepsEqualOpenAndCloseAndHasValidDomain() {
        let candle = PriceCandle(date: Date(), open: 100, high: 100, low: 100, close: 100)
        let series = ChartSeries(candles: [candle], fetchedAt: Date())
        XCTAssertTrue(candle.isValid)
        XCTAssertEqual(series.candles[0].open, series.candles[0].close)
        XCTAssertEqual(series.changePercent, 0)
        XCTAssertLessThan(series.domain.lowerBound, series.domain.upperBound)
    }

    func testOldSavedQuotesDecodeWithoutOHLCAndDoNotInventIt() throws {
        let data = Data(#"{"instrumentID":"binance:BTCUSDT","price":100,"changePercent":1,"currency":"USDT","marketDate":100,"fetchedAt":100,"marketOpen":true,"points":[{"date":100,"value":100}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(MarketSnapshot.self, from: data)
        XCTAssertEqual(snapshot.price, 100)
        XCTAssertEqual(snapshot.points.count, 1)
        XCTAssertNil(snapshot.candles)
    }

    func testRangeChangeUsesFirstOpenAndLastClose() {
        let candles: [PriceCandle] = [
            .init(date: Date(timeIntervalSince1970: 0), open: 100, high: 112, low: 95, close: 110),
            .init(date: Date(timeIntervalSince1970: 300), open: 110, high: 111, low: 85, close: 90)
        ]
        let series = ChartSeries(candles: candles, fetchedAt: Date())
        XCTAssertEqual(series.changePercent, -10)
        XCTAssertEqual(series.points.map(\.value), [110, 90])
    }
}

private final class CandleURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    static func recorded() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let data: Data
        if request.url!.host == "data-api.binance.vision" {
            data = Data(#"[[1000,"100","110","90","105"]]"#.utf8)
        } else {
            let bucket = floor(Date().timeIntervalSince1970 / 14400) * 14400 - 14400
            let quote: [String: Any] = ["open": [100,102,103,100], "high": [105,107,108,104], "low": [98,101,99,97], "close": [102,103,100,104]]
            let result: [String: Any] = ["meta": [:], "timestamp": (0..<4).map { bucket + Double($0) * 3600 }, "indicators": ["quote": [quote]]]
            data = try! JSONSerialization.data(withJSONObject: ["chart": ["result": [result], "error": NSNull()]])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CandleTransportTests: XCTestCase {
    private func session() -> URLSession {
        CandleURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CandleURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testBinanceRequestsReadableCandleIntervalsAndEnoughHistory() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = MarketService(session: session)
        for range in ChartRange.allCases { _ = try await service.history(for: Instrument.defaults[2], range: range) }
        let requests = CandleURLProtocol.recorded()
        let params = requests.map { Dictionary(uniqueKeysWithValues: URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") }) }
        XCTAssertEqual(params.map { $0["interval"] }, ["5m", "30m", "4h", "1d"])
        XCTAssertEqual(params.map { $0["limit"] }, ["50", "50", "44", "32"])
    }

    func testYahooWeekRequestsRealHourlyOHLCAndAggregatesFourHours() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let series = try await MarketService(session: session).history(for: Instrument.defaults[0], range: .week)
        let params = URLComponents(url: try XCTUnwrap(CandleURLProtocol.recorded().first?.url), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "interval" }?.value, "1h")
        XCTAssertEqual(series.candles.count, 1)
        let candle = try XCTUnwrap(series.candles.first)
        XCTAssertEqual(candle.open, 100)
        XCTAssertEqual(candle.high, 108)
        XCTAssertEqual(candle.low, 97)
        XCTAssertEqual(candle.close, 104)
    }
}
