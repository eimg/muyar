import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

private actor HistoryTestService: MarketServing {
    enum Mode { case normal, fail, empty, delayedShort, closedSessions }
    private var mode: Mode = .normal
    private var emptyRequestsRemaining = 0
    private(set) var shortRequestStarted = false
    func setMode(_ value: Mode) { mode = value }
    func closeNextPages(_ count: Int) { mode = .closedSessions; emptyRequestsRemaining = count }
    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage {
        if mode == .fail { throw URLError(.notConnectedToInternet) }
        if mode == .empty { return .init(samples: [], fetchedAt: Date(), nextBefore: nil) }
        if mode == .closedSessions && emptyRequestsRemaining > 0 {
            emptyRequestsRemaining -= 1
            return .init(samples: [], fetchedAt: Date(), nextBefore: before.addingTimeInterval(-86400))
        }
        if mode == .delayedShort && range == .fourHours {
            shortRequestStarted = true
            try await Task.sleep(for: .milliseconds(80))
        }
        let end = floor(before.timeIntervalSince1970 / range.candleDuration) * range.candleDuration
        let samples: [ChartSample] = (0..<200).map { index in
            let date = Date(timeIntervalSince1970: end - Double(200 - index) * range.candleDuration)
            // A large old wick must not flatten a viewport of recent bars.
            let high = index == 0 ? 100000.0 : 110.0
            let candle = PriceCandle(date: date, open: 100, high: high, low: 90, close: 105)
            return .init(date: date, close: 105, candle: candle)
        }
        return .init(samples: samples, fetchedAt: Date(), nextBefore: samples.first!.date)
    }
    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot { throw MarketError.noData }
    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries { throw MarketError.noData }
    func p2p(buy: Bool) async throws -> P2PSide { throw MarketError.noData }
    func search(_ query: String, crypto: Bool) async throws -> [Instrument] { [] }
}

final class ChartHistoryPolicyTests: XCTestCase {
    func testLineCanUseCloseOnlyDataWithoutInventingCandles() {
        let points: [PricePoint] = [.init(date: Date(timeIntervalSince1970: 10), value: 100), .init(date: Date(timeIntervalSince1970: 310), value: 105)]
        let samples = ChartHistoryPolicy.samples(points: points, candles: [], interval: 300)
        XCTAssertEqual(samples.map(\.close), [100, 105])
        XCTAssertTrue(samples.allSatisfy { $0.candle == nil })
    }

    func testClosedSessionsDoNotCreatePlaceholderObservations() {
        let times: [Double] = [0, 300, 86400 * 3]
        let samples = ChartHistoryPolicy.samples(points: times.map { .init(date: Date(timeIntervalSince1970: $0), value: 100) }, candles: [], interval: 300)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.date.timeIntervalSince1970), times)
    }

    func testLineCloseAndCandleStayIndependentWhenLatestOHLCIsMissing() {
        let points: [PricePoint] = [.init(date: Date(timeIntervalSince1970: 0), value: 102), .init(date: Date(timeIntervalSince1970: 3600), value: 110)]
        let candle = PriceCandle(date: points[0].date, open: 100, high: 105, low: 99, close: 102)
        let samples = ChartHistoryPolicy.samples(points: points, candles: [candle], interval: 14400)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].close, 110)
        XCTAssertEqual(samples[0].candle?.close, 102)
        XCTAssertEqual(samples[0].candle?.high, 105)
    }

    func testSourceLimitsDependOnIntervalAndProvider() {
        let now = Date(timeIntervalSince1970: 2000000000)
        XCTAssertEqual(now.timeIntervalSince(ChartHistoryPolicy.earliest(provider: .yahoo, range: .day, now: now)), 59 * 86400)
        XCTAssertEqual(now.timeIntervalSince(ChartHistoryPolicy.earliest(provider: .yahoo, range: .week, now: now)), 729 * 86400)
        XCTAssertGreaterThan(now.timeIntervalSince(ChartHistoryPolicy.earliest(provider: .binance, range: .fourHours, now: now)), 3650 * 86400)
    }
}

@MainActor
final class ChartHistoryStoreTests: XCTestCase {
    private func model(_ service: HistoryTestService) -> ChartHistoryStore {
        .init(instrument: Instrument.defaults[2], service: service)
    }

    func testInitialViewportShowsLatestPresetWindow() async {
        let chart = model(HistoryTestService())
        await chart.load(range: .day)
        XCTAssertEqual(chart.samples.count, 200)
        XCTAssertEqual(chart.visibleSamples.count, 48)
        XCTAssertEqual(chart.visibleSamples.last?.date, chart.samples.last?.date)
        XCTAssertTrue(chart.includesLatest)
    }

    func testVisibleScaleIgnoresOffscreenWicksAndIncludesVisibleWicks() async {
        let chart = model(HistoryTestService())
        await chart.load(range: .day)
        XCTAssertLessThan(chart.yDomain(style: .candles).upperBound, 1000)
        chart.setPosition(-0.5)
        XCTAssertGreaterThan(chart.yDomain(style: .candles).upperBound, 100000)
        XCTAssertLessThan(chart.yDomain(style: .line).upperBound, 1000)
    }

    func testZoomPreservesMiddleDateAndClampsToAvailableData() async {
        let chart = model(HistoryTestService())
        await chart.load(range: .day)
        chart.setPosition(70)
        let anchor = chart.anchorDate
        chart.zoom(to: 16, around: anchor)
        XCTAssertEqual(chart.anchorDate, anchor)
        XCTAssertEqual(chart.visibleCount, 16)
        chart.zoom(to: 1)
        XCTAssertEqual(chart.visibleCount, 8)
        chart.zoom(to: 10000)
        XCTAssertEqual(chart.visibleCount, 160)
        chart.zoom(to: .infinity)
        XCTAssertEqual(chart.visibleCount, 160)
    }

    func testEarlierPagePreservesVisibleDateAndHasNoDuplicates() async throws {
        let chart = model(HistoryTestService())
        await chart.load(range: .day)
        chart.setPosition(10)
        let anchor = try XCTUnwrap(chart.visibleSamples.first?.date)
        let oldCursor = try XCTUnwrap(chart.nextBefore)
        await chart.loadEarlier(force: true)
        XCTAssertEqual(chart.samples.count, 400)
        XCTAssertEqual(chart.visibleSamples.first?.date, anchor)
        XCTAssertEqual(Set(chart.samples.map(\.date)).count, chart.samples.count)
        XCTAssertLessThan(try XCTUnwrap(chart.nextBefore), oldCursor)
    }

    func testDateJumpAndNewerPagingPreserveHistoricalViewport() async throws {
        let chart = model(HistoryTestService())
        let end = Date().addingTimeInterval(-365 * 86400)
        await chart.load(range: .month, endingAt: end)
        XCTAssertFalse(chart.includesLatest)
        XCTAssertLessThan(try XCTUnwrap(chart.samples.last?.date), end)
        let anchor = chart.visibleSamples.first?.date
        let oldLast = try XCTUnwrap(chart.samples.last?.date)
        await chart.loadNewerIfNeeded()
        XCTAssertEqual(chart.visibleSamples.first?.date, anchor)
        XCTAssertGreaterThan(try XCTUnwrap(chart.samples.last?.date), oldLast)
        await chart.load(range: .month)
        XCTAssertTrue(chart.includesLatest)
        XCTAssertEqual(chart.visibleSamples.last?.date, chart.samples.last?.date)
    }

    func testYesterdayJumpDoesNotPretendToIncludeCurrentDailyBar() async {
        let chart = model(HistoryTestService())
        await chart.load(range: .month, endingAt: Date().addingTimeInterval(-12 * 3600))
        XCTAssertFalse(chart.includesLatest)
    }

    func testFailedPagingPreservesDataAndViewport() async {
        let service = HistoryTestService()
        let chart = model(service)
        await chart.load(range: .day)
        let samples = chart.samples
        let position = chart.position
        await service.setMode(.fail)
        await chart.loadEarlier(force: true)
        XCTAssertEqual(chart.samples, samples)
        XCTAssertEqual(chart.position, position)
        XCTAssertNotNil(chart.error)
        XCTAssertFalse(chart.isLoadingEarlier)
    }

    func testOlderIntervalResponseCannotOverwriteNewInterval() async {
        let service = HistoryTestService()
        await service.setMode(.delayedShort)
        let chart = model(service)
        let old = Task { await chart.load(range: .fourHours) }
        while !(await service.shortRequestStarted) { await Task.yield() }
        await chart.load(range: .month)
        await old.value
        XCTAssertEqual(chart.range, .month)
        XCTAssertEqual(chart.samples[1].date.timeIntervalSince(chart.samples[0].date), 86400)
    }

    func testEmptyPageIsAStableEmptyState() async {
        let service = HistoryTestService()
        await service.setMode(.empty)
        let chart = model(service)
        await chart.load(range: .week)
        XCTAssertTrue(chart.samples.isEmpty)
        XCTAssertFalse(chart.hasEarlier)
        XCTAssertFalse(chart.isLoading)
        XCTAssertNil(chart.error)
    }

    func testNewerPagingCrossesEmptySessionsWithoutGettingStuck() async throws {
        let service = HistoryTestService()
        let chart = model(service)
        await chart.load(range: .fourHours, endingAt: Date().addingTimeInterval(-10 * 86400))
        let last = try XCTUnwrap(chart.samples.last?.date)
        let anchor = chart.visibleSamples.first?.date
        await service.closeNextPages(8)
        await chart.loadNewerIfNeeded()
        XCTAssertGreaterThan(try XCTUnwrap(chart.samples.last?.date), last)
        XCTAssertEqual(chart.visibleSamples.first?.date, anchor)
        XCTAssertNil(chart.error)
    }

    func testRetryPreservesTheFailedHistoricalDateRequest() async throws {
        let service = HistoryTestService()
        let chart = model(service)
        let end = Date().addingTimeInterval(-300 * 86400)
        await service.setMode(.fail)
        await chart.load(range: .month, endingAt: end)
        XCTAssertNotNil(chart.error)
        await service.setMode(.normal)
        await chart.retry()
        XCTAssertFalse(chart.includesLatest)
        XCTAssertLessThan(try XCTUnwrap(chart.samples.last?.date), end)
        XCTAssertNil(chart.error)
    }
}

private final class HistoryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    static func recorded() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let url = request.url!
        let params = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        let data: Data
        if url.host == "data-api.binance.vision" {
            let end = Double(params["endTime"]!)! / 1000
            let rows: [[Any]] = (1...3).reversed().map { [(end - Double($0) * 86400) * 1000, "100", "110", "90", "105"] }
            data = try! JSONSerialization.data(withJSONObject: rows)
        } else {
            let end = Double(params["period2"]!)!
            let result: [String: Any] = ["meta": ["firstTradeDate": end - 100 * 86400], "timestamp": [end - 2 * 86400, end - 86400], "indicators": ["quote": [["close": [100, 105]]]]]
            data = try! JSONSerialization.data(withJSONObject: ["chart": ["result": [result], "error": NSNull()]])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ChartHistoryTransportTests: XCTestCase {
    private func session() -> URLSession {
        HistoryURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HistoryURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testBinanceHistoricalPageUsesExclusiveBeforeInMilliseconds() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let end = Date().addingTimeInterval(-365 * 86400)
        let page = try await MarketService(session: session).historyPage(for: Instrument.defaults[2], range: .month, before: end)
        let url = try XCTUnwrap(HistoryURLProtocol.recorded().first?.url)
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "endTime" }?.value, String(Int64(ceil(end.timeIntervalSince1970 * 1000)) - 1))
        XCTAssertEqual(params.first { $0.name == "limit" }?.value, "200")
        XCTAssertEqual(page.samples.count, 3)
        XCTAssertTrue(page.samples.allSatisfy { $0.date < end })
        XCTAssertNotNil(page.nextBefore)
    }

    func testYahooHistoricalPageUsesPeriodBoundsAndRetainsCloseOnlyPrices() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let end = Date().addingTimeInterval(-365 * 86400)
        let page = try await MarketService(session: session).historyPage(for: Instrument.defaults[4], range: .month, before: end)
        let url = try XCTUnwrap(HistoryURLProtocol.recorded().first?.url)
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertNotNil(params.first { $0.name == "period1" })
        XCTAssertEqual(params.first { $0.name == "period2" }?.value, String(Int(ceil(end.timeIntervalSince1970))))
        XCTAssertNil(params.first { $0.name == "range" })
        XCTAssertEqual(page.samples.map(\.close), [100, 105])
        XCTAssertTrue(page.samples.allSatisfy { $0.candle == nil })
        XCTAssertNil(page.nextBefore) // the page has reached the instrument's listing date
    }

    func testBeforeSourceBoundaryDoesNotMakeAnUnsupportedRequest() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let page = try await MarketService(session: session).historyPage(for: Instrument.defaults[4], range: .fourHours, before: Date().addingTimeInterval(-100 * 86400))
        XCTAssertTrue(page.samples.isEmpty)
        XCTAssertNil(page.nextBefore)
        XCTAssertTrue(HistoryURLProtocol.recorded().isEmpty)
    }

    func testYahooPagingStartsOnAnAggregationBoundary() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        _ = try await MarketService(session: session).historyPage(for: Instrument.defaults[4], range: .week, before: Date().addingTimeInterval(-10 * 86400))
        let url = try XCTUnwrap(HistoryURLProtocol.recorded().first?.url)
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let start = try XCTUnwrap(params.first { $0.name == "period1" }?.value.flatMap(Double.init))
        XCTAssertEqual(start.truncatingRemainder(dividingBy: ChartRange.week.candleDuration), 0)
    }
}
