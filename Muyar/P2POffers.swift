import Foundation
import Combine

/// All directions describe what the viewer does, not what the advertiser does.
enum P2PTradeSide: String, CaseIterable, Identifiable, Sendable {
    case buy = "BUY", sell = "SELL"
    var id: String { rawValue }
    var title: String { self == .buy ? "Buy USDT" : "Sell USDT" }
    var counterparty: String { self == .buy ? "Seller" : "Buyer" }
    var explanation: String { self == .buy ? "You pay MMK · Sellers offering USDT" : "You receive MMK · Buyers wanting USDT" }
    var sortLabel: String { self == .buy ? "Lowest price first" : "Highest price first" }
}

struct P2POffer: Identifiable, Equatable, Sendable {
    let id: String
    let price: Double
    let merchant: String
    let minMMK: Double?
    let maxMMK: Double?
    let availableUSDT: Double?
    let paymentMethods: [String]
    let completionRate: Double?
    let monthlyOrders: Int?
}

struct P2POfferBook: Sendable {
    let side: P2PTradeSide
    let offers: [P2POffer]
    let fetchedAt: Date
    let returnedCount: Int
    let omittedCount: Int
}

enum P2POfferParsing {
    static func book(_ data: Data, side: P2PTradeSide, methods: [String: String] = [:], now: Date = Date()) throws -> P2POfferBook {
        let response = try JSONDecoder().decode(OfferResponse.self, from: data)
        guard response.success, response.code == "000000", let items = response.data?.items else {
            throw MarketError.invalidResponse
        }
        var seen = Set<String>()
        let valid: [P2POffer] = items.compactMap { row in
            guard row.asset == "USDT", row.fiat == "MMK", !row.adNo.isEmpty,
                  row.price.value.isFinite, row.price.value > 0,
                  !row.advertiser.nickName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let minimum = row.minTransAmount?.value
            let maximum = row.maxTransAmount?.value
            let available = row.tradableAmount?.value
            if let minimum, !minimum.isFinite || minimum < 0 { return nil }
            if let maximum, !maximum.isFinite || maximum <= 0 { return nil }
            if let minimum, let maximum, minimum > maximum { return nil }
            if let available, !available.isFinite || available <= 0 { return nil }
            guard seen.insert(row.adNo).inserted else { return nil }
            let rate = row.advertiser.monthFinishRate?.value
            return .init(id: row.adNo, price: row.price.value, merchant: row.advertiser.nickName,
                         minMMK: minimum, maxMMK: maximum, availableUSDT: available,
                         paymentMethods: row.tradeMethods.map { methods[$0] ?? $0 },
                         completionRate: rate.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil },
                         monthlyOrders: row.advertiser.monthOrderCount.flatMap { $0 >= 0 ? $0 : nil })
        }
        // A response full of invalid rows must not look like a successful empty market.
        guard items.isEmpty || !valid.isEmpty else { throw MarketError.invalidResponse }
        let sorted = valid.sorted {
            if $0.price == $1.price { return $0.id < $1.id }
            return side == .buy ? $0.price < $1.price : $0.price > $1.price
        }
        return .init(side: side, offers: Array(sorted.prefix(5)), fetchedAt: now,
                     returnedCount: items.count, omittedCount: items.count - valid.count)
    }

    static func methods(_ data: Data) throws -> [String: String] {
        let response = try JSONDecoder().decode(MethodResponse.self, from: data)
        guard response.success, response.code == "000000" else { throw MarketError.invalidResponse }
        return (response.data ?? []).reduce(into: [:]) { map, method in map[method.identifier] = method.tradeMethodName }
    }
}

private struct SourceNumber: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { value = number; return }
        let string = try container.decode(String.self)
        guard let number = Double(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected numeric price or quantity")
        }
        value = number
    }
}

private struct OfferResponse: Decodable {
    let code: String
    let success: Bool
    let data: Body?
    struct Body: Decodable { let items: [Offer] }
    struct Offer: Decodable {
        let adNo: String
        let asset: String
        let fiat: String
        let price: SourceNumber
        let minTransAmount: SourceNumber?
        let maxTransAmount: SourceNumber?
        let tradableAmount: SourceNumber?
        let tradeMethods: [String]
        let advertiser: Advertiser
    }
    struct Advertiser: Decodable {
        let nickName: String
        let monthOrderCount: Int?
        let monthFinishRate: SourceNumber?
    }
}

private struct MethodResponse: Decodable {
    let code: String
    let success: Bool
    let data: [Method]?
    struct Method: Decodable { let identifier: String, tradeMethodName: String }
}

@MainActor
final class P2POffersStore: ObservableObject {
    @Published private(set) var books: [P2PTradeSide: P2POfferBook] = [:]
    @Published private(set) var errors: [P2PTradeSide: String] = [:]
    @Published private(set) var isRefreshing = false
    private let service: any MarketServing
    init(service: any MarketServing) { self.service = service }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: Void.self) { group in
            for side in P2PTradeSide.allCases {
                group.addTask { await self.refresh(side) }
            }
        }
    }

    private func refresh(_ side: P2PTradeSide) async {
        do {
            let book = try await service.p2pOffers(side: side)
            guard !Task.isCancelled else { return }
            guard book.side == side else { throw MarketError.invalidResponse }
            books[side] = book
            errors.removeValue(forKey: side)
        } catch {
            guard !Task.isCancelled else { return }
            // Keep a prior successful book, but always label it as saved when this fails.
            errors[side] = "Refresh failed"
        }
    }
}
