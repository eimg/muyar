import XCTest
#if canImport(Muyar)
@testable import Muyar
#else
@testable import MuyarCore
#endif

final class InstrumentBrandTests: XCTestCase {
    private func crypto(_ symbol: String, quote: String) -> Instrument {
        .init(symbol: symbol, name: symbol, category: .crypto, provider: .binance, currency: quote, exchange: "Binance", unit: nil)
    }

    func testCryptoBrandFollowsTheBaseAssetAcrossQuotes() {
        XCTAssertEqual(crypto("BTCUSDT", quote: "USDT").brand, .bitcoin)
        XCTAssertEqual(crypto("BTCEUR", quote: "EUR").brand, .bitcoin)
        XCTAssertEqual(crypto("ETHBTC", quote: "BTC").brand, .ethereum)
        XCTAssertEqual(crypto("SOLUSDC", quote: "USDC").brand, .solana)
    }

    func testSimilarTickersDoNotBorrowAnotherAssetsBrand() {
        XCTAssertNil(crypto("BTCUPUSDT", quote: "USDT").brand)
        XCTAssertNil(crypto("ETHFIUSDT", quote: "USDT").brand)
        XCTAssertNil(crypto("BTCUSDT", quote: "USD").brand)
        XCTAssertNil(crypto("BTCUSDT", quote: "").brand)
    }

    func testKnownStockTickersAndUnknownFallback() {
        let apple = Instrument.defaults.first { $0.symbol == "AAPL" }!
        XCTAssertEqual(apple.brand, .apple)
        XCTAssertEqual(Instrument.defaults.first { $0.symbol == "NVDA" }?.brand, .nvidia)
        XCTAssertEqual(Instrument.suggestions.first { $0.symbol == "MSFT" }?.brand, .microsoft)
        XCTAssertEqual(Instrument.suggestions.first { $0.symbol == "TSLA" }?.brand, .tesla)
        XCTAssertNil(Instrument.defaults.first { $0.symbol == "GC=F" }?.brand)
        XCTAssertNil(Instrument(symbol: "AAPLX", name: "Apple-like name", category: .stocks, provider: .yahoo, currency: "USD", exchange: "", unit: nil).brand)
    }

    func testCatalogCoversUnwatchedCompaniesAndCrypto() {
        XCTAssertGreaterThanOrEqual(InstrumentBrand.allCases.count, 100)
        for (symbol, brand) in [("AMZN", InstrumentBrand.amazon), ("GOOGL", .google), ("NET", .cloudflare), ("RDDT", .reddit), ("SONY", .sony)] {
            let item = Instrument(symbol: symbol, name: symbol, category: .stocks, provider: .yahoo, currency: "USD", exchange: "", unit: nil)
            XCTAssertEqual(item.brand, brand)
        }
        XCTAssertEqual(crypto("SUIUSDT", quote: "USDT").brand, .sui)
        XCTAssertEqual(crypto("TONUSDC", quote: "USDC").brand, .ton)
        XCTAssertEqual(crypto("POLBTC", quote: "BTC").brand, .polygon)
        XCTAssertEqual(crypto("MATICUSDT", quote: "USDT").brand, .polygon)
    }

    func testReservedBrandsDoNotInventTradeableSymbols() {
        for reserved in [InstrumentBrand.spacex, .anthropic, .openai] {
            XCTAssertFalse(InstrumentBrand.stocksSymbols.values.contains(reserved))
            XCTAssertFalse(InstrumentBrand.cryptoSymbols.values.contains(reserved))
        }
    }

    func testCommodityIconsAreProviderSpecific() {
        XCTAssertEqual(Instrument.defaults[0].glyph, .goldBrick)
        XCTAssertEqual(Instrument.defaults[1].glyph, .oil)
        let dollar = Instrument(symbol: "DX-Y.NYB", name: "US Dollar Index", category: .stocks, provider: .yahoo, currency: "", exchange: "", unit: nil)
        XCTAssertEqual(dollar.glyph, .dollar)
        XCTAssertNil(crypto("DX-Y.NYB", quote: "NYB").glyph)
    }
}
