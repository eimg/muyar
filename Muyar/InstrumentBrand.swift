import Foundation

enum InstrumentBrand: String, CaseIterable {
    case bitcoin, ethereum, apple, nvidia, microsoft, tesla, solana
    case binance, tether, dogecoin, cardano, litecoin, ripple

    var assetName: String { "Brand-\(rawValue)" }
}

extension Instrument {
    var brand: InstrumentBrand? {
        switch provider {
        case .binance:
            guard category == .crypto, !currency.isEmpty, symbol.hasSuffix(currency), symbol.count > currency.count else { return nil }
            // Match the exact base asset, never a prefix such as BTCUP or ETHFI.
            switch String(symbol.dropLast(currency.count)) {
            case "BTC": return .bitcoin
            case "ETH": return .ethereum
            case "SOL": return .solana
            case "BNB": return .binance
            case "USDT": return .tether
            case "DOGE": return .dogecoin
            case "ADA": return .cardano
            case "LTC": return .litecoin
            case "XRP": return .ripple
            default: return nil
            }
        case .yahoo:
            guard category == .stocks else { return nil }
            switch symbol {
            case "AAPL": return .apple
            case "NVDA": return .nvidia
            case "MSFT": return .microsoft
            case "TSLA": return .tesla
            default: return nil
            }
        }
    }
}
