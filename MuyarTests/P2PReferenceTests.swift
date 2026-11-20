import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

private final class ReferenceQuoteURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    static func recorded() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let url = request.url!
        let side = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "tradeType" }?.value
        let price = side == "BUY" ? 5160 : 5148
        let data = Data("{\"code\":\"000000\",\"success\":true,\"data\":{\"asset\":\"USDT\",\"fiat\":\"MMK\",\"price\":\(price)}}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class P2PReferenceTests: XCTestCase {
    func testUnauthenticatedP2PUsesOnlyDirectionalReferenceQuotes() async throws {
        ReferenceQuoteURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReferenceQuoteURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = MarketService(session: session)
        let buy = try await service.p2p(buy: true)
        let sell = try await service.p2p(buy: false)
        XCTAssertEqual(buy.price, 5160)
        XCTAssertEqual(sell.price, 5148)
        let requests = ReferenceQuoteURLProtocol.recorded()
        XCTAssertEqual(requests.count, 2)
        var directions = Set<String>()
        for request in requests {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "www.binance.com")
            XCTAssertEqual(url.path, "/bapi/c2c/v1/public/c2c/agent/quote-price")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["asset"], "USDT")
            XCTAssertEqual(query["fiat"], "MMK")
            directions.insert(try XCTUnwrap(query["tradeType"]))
        }
        XCTAssertEqual(directions, ["BUY", "SELL"])
    }
}
