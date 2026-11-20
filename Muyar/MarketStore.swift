import Foundation
import Combine

struct SavedMarketState: Codable {
    var instruments: [Instrument]
    var snapshots: [String: MarketSnapshot]
    var p2p: P2PQuotes
}

@MainActor
final class MarketStore: ObservableObject {
    @Published private(set) var instruments: [Instrument]
    @Published private(set) var snapshots: [String: MarketSnapshot]
    @Published private(set) var p2pQuotes: P2PQuotes
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var persistenceError: String?
    let service: any MarketServing
    private let cacheURL: URL
    private var refreshingIDs = Set<String>()

    init(service: any MarketServing = MarketService(), cacheURL: URL? = nil) {
        self.service = service
        self.cacheURL = cacheURL ?? Self.defaultCacheURL
        if let data = try? Data(contentsOf: self.cacheURL), let saved = try? JSONDecoder().decode(SavedMarketState.self, from: data) {
            var seen = Set<String>()
            instruments = saved.instruments.filter { seen.insert($0.id).inserted }
            snapshots = saved.snapshots.filter { seen.contains($0.key) }
            p2pQuotes = saved.p2p
        } else {
            instruments = Instrument.defaults
            snapshots = [:]
            p2pQuotes = .init()
        }
    }

    private static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Muyar", isDirectory: true).appendingPathComponent("market-state.json")
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let state = SavedMarketState(instruments: instruments, snapshots: snapshots, p2p: p2pQuotes)
            try JSONEncoder().encode(state).write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            persistenceError = nil
        } catch {
            persistenceError = "Save failed"
        }
    }

    func add(_ instrument: Instrument) {
        guard !instruments.contains(where: { $0.id == instrument.id }) else { return }
        instruments.append(instrument)
        save()
        Task { await refreshInstrument(instrument) }
    }

    func remove(at offsets: IndexSet) {
        let ids = offsets.compactMap { instruments.indices.contains($0) ? instruments[$0].id : nil }
        instruments = instruments.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        for id in ids { snapshots.removeValue(forKey: id); errors.removeValue(forKey: id) }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        let moved = source.sorted().map { instruments[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        instruments = instruments.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        instruments.insert(contentsOf: moved, at: min(insertion, instruments.count))
        save()
    }

    func refreshInstrument(_ instrument: Instrument) async {
        guard refreshingIDs.insert(instrument.id).inserted else { return }
        defer { refreshingIDs.remove(instrument.id) }
        do {
            let snapshot = try await service.snapshot(for: instrument)
            guard instruments.contains(where: { $0.id == instrument.id }), !Task.isCancelled else { return }
            snapshots[instrument.id] = snapshot
            errors.removeValue(forKey: instrument.id)
        } catch {
            if !Task.isCancelled, instruments.contains(where: { $0.id == instrument.id }) {
                errors[instrument.id] = Self.message(error)
            }
        }
        save()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: Void.self) { group in
            for instrument in instruments {
                group.addTask { await self.refreshInstrument(instrument) }
            }
            group.addTask { await self.refreshP2P(buy: true) }
            group.addTask { await self.refreshP2P(buy: false) }
        }
        save()
    }

    private func refreshP2P(buy: Bool) async {
        let key = buy ? "p2p-buy" : "p2p-sell"
        do {
            let side = try await service.p2p(buy: buy)
            guard !Task.isCancelled else { return }
            if buy { p2pQuotes.buy = side } else { p2pQuotes.sell = side }
            errors.removeValue(forKey: key)
        } catch {
            if !Task.isCancelled { errors[key] = Self.message(error) }
        }
    }

    static func message(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return "Offline"
            case .timedOut: return "Request timed out"
            default: return "Source unavailable"
            }
        }
        if error is DecodingError { return "Invalid response" }
        return error.localizedDescription
    }
}
