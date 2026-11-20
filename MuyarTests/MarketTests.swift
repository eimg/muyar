import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

final class MarketParsingTests: XCTestCase {
    func testP2PQuoteHasExplicitFetchTime() throws {
        let date = Date(timeIntervalSince1970: 100)
        let raw = Data(#"{"code":"000000","success":true,"data":{"asset":"USDT","fiat":"MMK","price":5160}}"#.utf8)
        let quote = try MarketParsing.p2p(raw, now: date)
        XCTAssertEqual(quote.price, 5160)
        XCTAssertEqual(quote.fetchedAt, date)
    }

    func testP2PRejectsFailedEmptyWrongCurrencyAndZeroQuotes() {
        for json in [
            #"{"code":"100001","success":false,"data":null}"#,
            #"{"code":"000000","success":true,"data":null}"#,
            #"{"code":"000000","success":true,"data":{"asset":"USDT","fiat":"USD","price":5160}}"#,
            #"{"code":"000000","success":true,"data":{"asset":"USDT","fiat":"MMK","price":0}}"#
        ] {
            XCTAssertThrowsError(try MarketParsing.p2p(Data(json.utf8), now: Date()))
        }
    }

    func testBinanceUsesCloseNotOpenAndConvertsMilliseconds() throws {
        let raw = Data(#"[[2000000,"100","105","95","103","1"],[1000000,"90","99","88","98","1"]]"#.utf8)
        let points = try MarketParsing.binancePoints(raw)
        XCTAssertEqual(points.map(\.value), [98, 103])
        XCTAssertEqual(points.map { $0.date.timeIntervalSince1970 }, [1000, 2000])
    }

    func testYahooNullValuesDoNotShiftTimestamps() throws {
        let raw = Data(#"{"chart":{"result":[{"meta":{},"timestamp":[10,20,30,40],"indicators":{"quote":[{"close":[100,null,102]}]}}],"error":null}}"#.utf8)
        let result = try MarketParsing.yahooResult(raw)
        XCTAssertEqual(result.points.map(\.value), [100, 102])
        XCTAssertEqual(result.points.map { $0.date.timeIntervalSince1970 }, [10, 30])
    }

    func testYahooSnapshotSeparatesQuoteTimeFromFetchTimeAndUsesPreviousClose() throws {
        let raw = Data(#"{"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":110,"regularMarketTime":100,"previousClose":100,"chartPreviousClose":90,"currentTradingPeriod":{"regular":{"start":50,"end":150}}}}],"error":null}}"#.utf8)
        let snapshot = try MarketParsing.yahooSnapshot(raw, instrument: Instrument.defaults[4], now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(snapshot.price, 110)
        XCTAssertEqual(try XCTUnwrap(snapshot.changePercent), 10, accuracy: 0.0001)
        XCTAssertEqual(snapshot.marketDate.timeIntervalSince1970, 100)
        XCTAssertEqual(snapshot.fetchedAt.timeIntervalSince1970, 200)
        XCTAssertFalse(snapshot.marketOpen)
    }

    func testYahooProviderErrorDoesNotBecomeAnEmptySuccess() {
        let raw = Data(#"{"chart":{"result":null,"error":{"description":"No data found"}}}"#.utf8)
        XCTAssertThrowsError(try MarketParsing.yahooResult(raw))
    }

    func testRangeMeansLookbackWindowAndRejectsFuturePoints() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(ChartRange.fourHours.contains(now.addingTimeInterval(-14_400), now: now))
        XCTAssertFalse(ChartRange.fourHours.contains(now.addingTimeInterval(-14_401), now: now))
        XCTAssertFalse(ChartRange.day.contains(now.addingTimeInterval(1), now: now))
        XCTAssertEqual(ChartRange.month.duration, 30 * 86400)
    }

    func testFlatAndTinyPriceDomainsStayValid() {
        let point = PricePoint(date: Date(), value: 0.00001)
        let series = ChartSeries(points: [point, point], fetchedAt: Date())
        XCTAssertLessThan(series.domain.lowerBound, point.value)
        XCTAssertGreaterThan(series.domain.upperBound, point.value)
        XCTAssertEqual(series.changePercent, 0)
    }

    func testCryptoQuoteAssetIsNotMislabelledAsUSD() {
        XCTAssertEqual(Instrument.defaults[2].displaySymbol, "BTC/USDT")
        XCTAssertFalse(PriceFormat.price(100, currency: "USDT").contains("$"))
        XCTAssertTrue(PriceFormat.price(100, currency: "USD").contains("$"))
    }
}

private struct FailingService: MarketServing {
    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage { throw MarketError.noData }
    func p2pOffers(side: P2PTradeSide) async throws -> P2POfferBook { throw URLError(.notConnectedToInternet) }
    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot { throw URLError(.notConnectedToInternet) }
    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries { throw URLError(.notConnectedToInternet) }
    func p2p(buy: Bool) async throws -> P2PSide { throw URLError(.notConnectedToInternet) }
    func search(_ query: String, crypto: Bool) async throws -> [Instrument] { [] }
}

private struct PartialP2PService: MarketServing {
    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage { throw MarketError.noData }
    func p2pOffers(side: P2PTradeSide) async throws -> P2POfferBook { throw URLError(.notConnectedToInternet) }
    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot { throw URLError(.notConnectedToInternet) }
    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries { throw URLError(.notConnectedToInternet) }
    func p2p(buy: Bool) async throws -> P2PSide {
        if buy { throw URLError(.timedOut) }
        return .init(price: 5200, fetchedAt: Date())
    }
    func search(_ query: String, crypto: Bool) async throws -> [Instrument] { [] }
}

@MainActor
final class MarketStoreTests: XCTestCase {
    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
    }

    func testFailedRefreshPreservesBothCachedP2PQuotesAndMarketPrices() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = MarketStore(service: PreviewMarketService(), cacheURL: url)
        await original.refresh()
        XCTAssertEqual(original.snapshots.count, Instrument.defaults.count)
        let offline = MarketStore(service: FailingService(), cacheURL: url)
        let originalPrice = offline.snapshots[Instrument.defaults[0].id]?.price
        await offline.refresh()
        XCTAssertEqual(offline.snapshots[Instrument.defaults[0].id]?.price, originalPrice)
        XCTAssertEqual(offline.p2pQuotes.buy?.price, 5160)
        XCTAssertEqual(offline.p2pQuotes.sell?.price, 5148)
        XCTAssertEqual(offline.errors.count, Instrument.defaults.count + 2)
        XCTAssertFalse(offline.isRefreshing)
    }

    func testAddingDuplicateDoesNotDuplicateWatchlist() {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MarketStore(service: FailingService(), cacheURL: url)
        store.add(Instrument.defaults[0])
        XCTAssertEqual(store.instruments.count, Instrument.defaults.count)
    }

    func testOneFailedP2PSideDoesNotHideTheOtherSuccessfulSide() async {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let initial = MarketStore(service: PreviewMarketService(), cacheURL: url)
        await initial.refresh()
        let partial = MarketStore(service: PartialP2PService(), cacheURL: url)
        await partial.refresh()
        XCTAssertEqual(partial.p2pQuotes.buy?.price, 5160)
        XCTAssertEqual(partial.p2pQuotes.sell?.price, 5200)
        XCTAssertNotNil(partial.errors["p2p-buy"])
        XCTAssertNil(partial.errors["p2p-sell"])
    }

    func testReorderAndRemovalPersistAcrossLaunches() {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MarketStore(service: FailingService(), cacheURL: url)
        let first = store.instruments[0]
        store.move(from: IndexSet(integer: 0), to: store.instruments.count)
        XCTAssertEqual(store.instruments.last, first)
        store.remove(at: IndexSet(integer: 0))
        let loaded = MarketStore(service: FailingService(), cacheURL: url)
        XCTAssertEqual(loaded.instruments, store.instruments)
        XCTAssertEqual(loaded.instruments.count, Instrument.defaults.count - 1)
    }

    func testIntentionallyEmptyWatchlistIsNotReplacedWithDefaults() {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MarketStore(service: FailingService(), cacheURL: url)
        store.remove(at: IndexSet(integersIn: 0..<store.instruments.count))
        XCTAssertTrue(MarketStore(service: FailingService(), cacheURL: url).instruments.isEmpty)
    }

    func testCorruptCacheRecoversToUsableInitialState() throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("incomplete json".utf8).write(to: url)
        let store = MarketStore(service: FailingService(), cacheURL: url)
        XCTAssertEqual(store.instruments, Instrument.defaults)
        XCTAssertTrue(store.snapshots.isEmpty)
    }
}
