import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

private func offerRow(_ id: String, price: Any, asset: String = "USDT", fiat: String = "MMK", minimum: Double = 100000, maximum: Double = 5000000, available: Double = 1000) -> [String: Any] {
    ["adNo": id, "price": price, "asset": asset, "fiat": fiat,
     "minTransAmount": minimum, "maxTransAmount": maximum, "tradableAmount": available,
     "tradeMethods": ["KBZPay1"],
     "advertiser": ["nickName": "Test merchant \(id)", "monthOrderCount": 124, "monthFinishRate": 0.998]]
}

private func offerResponse(_ rows: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["code": "000000", "success": true, "data": ["items": rows]])
}

final class P2POfferParsingTests: XCTestCase {
    func testBuyRanksFiveCheapestAndSellRanksFiveHighest() throws {
        let prices = [5164, 5100, 5160, 5168, 5150, 5155, 5170]
        let raw = try offerResponse(prices.enumerated().map { offerRow(String($0.offset), price: $0.element) })
        let buy = try P2POfferParsing.book(raw, side: .buy)
        let sell = try P2POfferParsing.book(raw, side: .sell)
        XCTAssertEqual(buy.offers.map(\.price), [5100, 5150, 5155, 5160, 5164])
        XCTAssertEqual(sell.offers.map(\.price), [5170, 5168, 5164, 5160, 5155])
        XCTAssertEqual(buy.side, .buy)
        XCTAssertEqual(sell.side, .sell)
        XCTAssertEqual(buy.returnedCount, 7)
    }

    func testNumbersStringsPaymentLabelsAndLongAdIDsArePreserved() throws {
        let id = "13955101566659584000"
        let raw = try offerResponse([offerRow(id, price: "5160.5")])
        let now = Date(timeIntervalSince1970: 1234)
        let book = try P2POfferParsing.book(raw, side: .buy, methods: ["KBZPay1": "KBZPay"], now: now)
        let offer = try XCTUnwrap(book.offers.first)
        XCTAssertEqual(offer.id, id)
        XCTAssertEqual(offer.price, 5160.5)
        XCTAssertEqual(offer.minMMK, 100000)
        XCTAssertEqual(offer.maxMMK, 5000000)
        XCTAssertEqual(offer.paymentMethods, ["KBZPay"])
        XCTAssertEqual(offer.completionRate, 0.998)
        XCTAssertEqual(offer.monthlyOrders, 124)
        XCTAssertEqual(book.fetchedAt, now)
    }

    func testWrongPairsInvalidLimitsSoldOutAndDuplicatesAreNotRanked() throws {
        let raw = try offerResponse([
            offerRow("valid", price: 5160), offerRow("valid", price: 5160),
            offerRow("wrong-asset", price: 1, asset: "BTC"), offerRow("wrong-fiat", price: 1, fiat: "CNY"),
            offerRow("zero", price: 0), offerRow("inverted", price: 2, minimum: 300, maximum: 100),
            offerRow("sold-out", price: 3, available: 0)
        ])
        let book = try P2POfferParsing.book(raw, side: .buy)
        XCTAssertEqual(book.offers.map(\.id), ["valid"])
        XCTAssertEqual(book.omittedCount, 6)
    }

    func testInvalidRowsAreNotReportedAsAnEmptyMarket() throws {
        let raw = try offerResponse([offerRow("invalid", price: 0)])
        XCTAssertThrowsError(try P2POfferParsing.book(raw, side: .buy))
    }

    func testEmptyMarketIsDifferentFromFailedResponse() throws {
        XCTAssertTrue(try P2POfferParsing.book(offerResponse([]), side: .buy).offers.isEmpty)
        let failed = Data(#"{"code":"100001","success":false,"data":null}"#.utf8)
        XCTAssertThrowsError(try P2POfferParsing.book(failed, side: .buy))
        let changedShape = Data(#"{"code":"000000","success":true,"data":{}}"#.utf8)
        XCTAssertThrowsError(try P2POfferParsing.book(changedShape, side: .buy))
    }

    func testViewerDirectionLabelsDoNotReverseBuyerAndSeller() {
        XCTAssertEqual(P2PTradeSide.buy.rawValue, "BUY")
        XCTAssertEqual(P2PTradeSide.buy.counterparty, "Seller")
        XCTAssertEqual(P2PTradeSide.sell.rawValue, "SELL")
        XCTAssertEqual(P2PTradeSide.sell.counterparty, "Buyer")
    }

    func testPublicPaymentMethodSchema() throws {
        let raw = Data(#"{"code":"000000","success":true,"data":[{"identifier":"KBZPay1","tradeMethodName":"KBZPay"}]}"#.utf8)
        XCTAssertEqual(try P2POfferParsing.methods(raw), ["KBZPay1": "KBZPay"])
    }
}

private actor OffersReplayService: MarketServing {
    func historyPage(for instrument: Instrument, range: ChartRange, before: Date) async throws -> HistoryPage { throw MarketError.noData }
    enum Mode { case populated, empty, buyFails, wrongSide }
    private var mode: Mode = .populated
    func setMode(_ mode: Mode) { self.mode = mode }
    func p2pOffers(side: P2PTradeSide) async throws -> P2POfferBook {
        if mode == .buyFails && side == .buy { throw URLError(.notConnectedToInternet) }
        let rows = mode == .empty ? [] : [offerRow("\(side.rawValue)-offer", price: 5160)]
        return try P2POfferParsing.book(offerResponse(rows), side: mode == .wrongSide ? (side == .buy ? .sell : .buy) : side)
    }
    func snapshot(for instrument: Instrument) async throws -> MarketSnapshot { throw MarketError.noData }
    func history(for instrument: Instrument, range: ChartRange) async throws -> ChartSeries { throw MarketError.noData }
    func p2p(buy: Bool) async throws -> P2PSide { throw MarketError.noData }
    func search(_ query: String, crypto: Bool) async throws -> [Instrument] { [] }
}

@MainActor
final class P2POffersStoreTests: XCTestCase {
    func testOneSideFailureKeepsItsSavedOffersAndRefreshesOtherSide() async throws {
        let service = OffersReplayService()
        let store = P2POffersStore(service: service)
        await store.refresh()
        let oldBuy = try XCTUnwrap(store.books[.buy])
        await service.setMode(.buyFails)
        await store.refresh()
        XCTAssertEqual(store.books[.buy]?.fetchedAt, oldBuy.fetchedAt)
        XCTAssertNotNil(store.errors[.buy])
        XCTAssertNil(store.errors[.sell])
        XCTAssertEqual(store.books[.sell]?.offers.count, 1)
        XCTAssertFalse(store.isRefreshing)
    }

    func testSuccessfulEmptyResponseClearsOldOffers() async {
        let service = OffersReplayService()
        let store = P2POffersStore(service: service)
        await store.refresh()
        XCTAssertEqual(store.books[.buy]?.offers.count, 1)
        await service.setMode(.empty)
        await store.refresh()
        XCTAssertTrue(store.books[.buy]?.offers.isEmpty == true)
        XCTAssertTrue(store.books[.sell]?.offers.isEmpty == true)
        XCTAssertTrue(store.errors.isEmpty)
    }

    func testMismatchedSideCannotReplaceTheCorrectBook() async throws {
        let service = OffersReplayService()
        let store = P2POffersStore(service: service)
        await store.refresh()
        let oldBuy = try XCTUnwrap(store.books[.buy])
        await service.setMode(.wrongSide)
        await store.refresh()
        XCTAssertEqual(store.books[.buy]?.offers, oldBuy.offers)
        XCTAssertNotNil(store.errors[.buy])
        XCTAssertNotNil(store.errors[.sell])
    }
}

private final class OffersURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    static func recorded() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let body = request.url!.path.hasSuffix("trade-methods")
            ? #"{"code":"000000","success":true,"data":[]}"#
            : #"{"code":"000000","success":true,"data":{"items":[]}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class P2POffersTransportTests: XCTestCase {
    func testActualRequestsUseViewerSidesAndMMKWithoutCredentials() async throws {
        OffersURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OffersURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = MarketService(session: session)
        _ = try await service.p2pOffers(side: .buy)
        _ = try await service.p2pOffers(side: .sell)
        let requests = OffersURLProtocol.recorded().filter { $0.url?.path.hasSuffix("ad-list") == true }
        XCTAssertEqual(requests.count, 2)
        var sides: [String] = []
        for request in requests {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "www.binance.com")
            let params = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(params["fiat"], "MMK")
            XCTAssertEqual(params["asset"], "USDT")
            XCTAssertEqual(params["limit"], "20")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-MBX-APIKEY"))
            sides.append(try XCTUnwrap(params["tradeType"]))
        }
        XCTAssertEqual(sides, ["BUY", "SELL"])
    }
}
